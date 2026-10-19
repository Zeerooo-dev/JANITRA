# Bundled appearance fonts

Roboto and its existing license remain unchanged. System font uses Flutter's platform default.

The following regular (400) and bold (700) TrueType faces were downloaded from the official Google Fonts CSS API and `fonts.gstatic.com` on October 19, 2026. The CSS endpoint selects the concrete font revisions. These are bundled assets; the app makes no font-download requests at runtime.

| Family | Official CSS source | Bundled license |
| --- | --- | --- |
| Geist | https://fonts.googleapis.com/css?family=Geist:400,700&display=swap | licenses/Geist-OFL.txt |
| Geist Mono | https://fonts.googleapis.com/css?family=Geist+Mono:400,700&display=swap | licenses/GeistMono-OFL.txt |
| Inter | https://fonts.googleapis.com/css?family=Inter:400,700&display=swap | licenses/Inter-OFL.txt |
| Noto Sans | https://fonts.googleapis.com/css?family=Noto+Sans:400,700&display=swap | licenses/NotoSans-OFL.txt |
| Open Sans | https://fonts.googleapis.com/css?family=Open+Sans:400,700&display=swap | licenses/OpenSans-OFL.txt |
| Poppins | https://fonts.googleapis.com/css?family=Poppins:400,700&display=swap | licenses/Poppins-OFL.txt |
| Atkinson Hyperlegible | https://fonts.googleapis.com/css?family=Atkinson+Hyperlegible:400,700&display=swap | licenses/AtkinsonHyperlegible-OFL.txt |
| Lora | https://fonts.googleapis.com/css?family=Lora:400,700&display=swap | licenses/Lora-OFL.txt |

Each added family's unmodified SIL Open Font License was obtained from its corresponding `ofl/<family>/OFL.txt` directory in https://github.com/google/fonts. License files are included in the APK and source archive. Font files were validated as TrueType data, checked for family/style metadata, and loaded by Flutter in automated tests.
