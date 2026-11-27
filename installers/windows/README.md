# Windows installer revision 3

See the root patch README for build instructions. This revision uses `r-localignr-windows` and downloads checksum-pinned official BLAST+ 2.17.0 and DIAMOND 2.2.8 archives at installation time. No local channel or redistributed engine package is required. Existing Swiss-Prot provisioning, launcher and manifest are retained. Default development target: `%LOCALAPPDATA%\LocAlignR-upstream-test`. Windows compilation and functional testing are still required. Preserve the canonical manifest in `installers/macos/payload/db_manifest.json`.
