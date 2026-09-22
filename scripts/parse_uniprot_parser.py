#!/usr/bin/env python3

import argparse
import gzip
import re


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
        description="Convert UniProt FASTA headers into a LocAlignR metadata TSV."
    )

    parser.add_argument(
        "fasta",
        help="Input FASTA file (.fa, .fasta, optionally .gz)"
    )

    parser.add_argument(
        "output",
        help="Output TSV file"
    )

    args = parser.parse_args()

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

    with open_maybe_gzip(args.fasta) as infile, open(args.output, "w") as outfile:

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


if __name__ == "__main__":
    main()
