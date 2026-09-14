"""`python3 -m readership`, which is what every nix/tools.nix wrapper runs."""

from readership.cli import main

raise SystemExit(main())
