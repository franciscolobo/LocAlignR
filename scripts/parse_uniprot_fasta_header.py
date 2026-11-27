#!/usr/bin/env python3

import argparse
import gzip
import re
import sys
from pathlib import Path


FIELD_RE = re.compile(r"\s([A-Z]{2})=")


def open_maybe_gzip(path):
    if path.endswith(".gz"):
        return gzip.open(path, "rt")
    return open(path, "r")


def parse_uniprot_header(header):
    """
    Parse a UniProt FASTA header.

    Example:
    >sp|Q6GZX4|001R_FRG3G Putative transcription factor 001R
    OS=Frog virus 3 (isolate Goorha)
    OX=654924
    GN=FV3-001R
    PE=4
    SV=1
    """

    header = header.lstrip(">").strip()

    first, rest = header.split(" ", 1) if " " in header else (header, "")

    parts = first.split("|")
    db, accession, entry_name = (parts + ["", "", ""])[:3]

    matches = list(FIELD_RE.finditer(rest))

    if matches:
        protein_name = rest[:matches[0].start()].strip()
    else:
        protein_name = rest.strip()

    fields = {
        # LocAlignR ID (must match FASTA identifier)
        "id": first,

        # Parsed UniProt fields
        "db": db,
        "accession": accession,
        "entry_name": entry_name,
        "protein_name": protein_name,
        "organism": "",
        "taxid": "",
        "gene": "",
        "protein_existence": "",
        "sequence_version": "",

        # Full header
        "raw_header": header,
    }

    tag_map = {
        "OS": "organism",
        "OX": "taxid",
        "GN": "gene",
        "PE": "protein_existence",
        "SV": "sequence_version",
    }

    for i, match in enumerate(matches):
        tag = match.group(1)

        start = match.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(rest)

        value = rest[start:end].strip()

        if tag in tag_map:
            fields[tag_map[tag]] = value

    return fields


def main():
    parser = argparse.ArgumentParser(
        description="Convert UniProt FASTA headers into a LocAlignR metadata TSV and taxonomy maps."
    )

    parser.add_argument(
        "fasta",
        help="Input FASTA file (.fa, .fasta, optionally .gz)"
    )

    parser.add_argument(
        "output",
        help="Output TSV file"
    )

    parser.add_argument("--blast-map", help="BLAST taxonomy map output path")
    parser.add_argument("--diamond-map", help="DIAMOND taxonomy map output path")
    args = parser.parse_args()

    stem = Path(args.output).with_suffix("")
    blast_map = Path(args.blast_map or f"{stem}.blast_taxid_map.tsv")
    diamond_map = Path(args.diamond_map or f"{stem}.diamond_taxid_map.tsv")
    paths = [Path(args.fasta), Path(args.output), blast_map, diamond_map]
    if len({p.resolve() for p in paths}) != len(paths):
        parser.error("Input and output paths must be distinct.")

    columns = [
        "id",
        "db",
        "accession",
        "entry_name",
        "protein_name",
        "organism",
        "taxid",
        "gene",
        "protein_existence",
        "sequence_version",
        "raw_header",
    ]

    total = mapped = skipped = duplicates = 0
    seen = {}
    with open_maybe_gzip(args.fasta) as infile, \
         open(args.output, "w") as outfile, \
         open(blast_map, "w", newline="\n") as blast_out, \
         open(diamond_map, "w", newline="\n") as diamond_out:

        diamond_out.write("accession\taccession.version\ttaxid\tgi\n")

        outfile.write("\t".join(columns) + "\n")

        for line in infile:
            if not line.startswith(">"):
                continue

            record = parse_uniprot_header(line)

            values = [
                str(record.get(col, "")).replace("\t", " ")
                for col in columns
            ]

            outfile.write("\t".join(values) + "\n")

            total += 1
            taxid = record["taxid"]
            accession = record["accession"]
            if (record["db"] not in ("sp", "tr") or not accession
                    or not re.fullmatch(r"[1-9][0-9]*", taxid)):
                skipped += 1
                continue

            # BLAST uses the complete FASTA identifier; DIAMOND's default
            # accession parser extracts the middle field of UniProt IDs.
            previous = seen.get(accession)
            if previous is not None and previous != taxid:
                raise SystemExit(f"Conflicting TaxIDs for {accession}: "
                                 f"{previous} and {taxid}. Outputs are incomplete.")
            blast_out.write(f"{record['id']}\t{taxid}\n")
            if previous is None:
                diamond_out.write(f"{accession}\t{accession}\t{taxid}\t0\n")
                seen[accession] = taxid
            else:
                duplicates += 1
            mapped += 1

    print(f"FASTA records: {total}; mapped: {mapped}; skipped: {skipped}; "
          f"duplicate DIAMOND accessions: {duplicates}", file=sys.stderr)
    print(f"Metadata: {args.output}\nBLAST map: {blast_map}\n"
          f"DIAMOND map: {diamond_map}", file=sys.stderr)
    if not mapped:
        raise SystemExit("No valid taxonomy mappings generated.")
    if skipped:
        print("Warning: skipped records remain in metadata but have no taxonomy mapping.",
              file=sys.stderr)


if __name__ == "__main__":
    main()
