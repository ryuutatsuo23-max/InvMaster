# Building a release

From the project root, run:

```text
python tools/build_release.py OUTPUT_DIRECTORY
```

The script reads the addon version and creates `InvMaster-vVERSION.zip` with one
`invmaster/` folder. Its explicit file list includes runtime modules, the root
`LICENSE` with DragoHorse's copyright notice, and existing third-party notices.
It verifies every archived file and refuses to overwrite an existing ZIP.
Tests, backups, settings and research files are excluded.

Build from a clean release commit. Publish the corresponding source tag alongside
the ZIP so source files, data generators and attribution remain available.
Keep third-party copyright and license notices intact.
