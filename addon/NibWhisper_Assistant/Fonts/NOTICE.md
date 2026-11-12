# Fonts in this folder

`Base.ttf` is Cascadia Code, copyright (c) Microsoft Corporation, used under the SIL Open Font License 1.1.
Source and licence text: https://github.com/microsoft/cascadia-code

Nib never displays this font. The helper copies two of its glyphs into small data fonts named `R0001.ttf` to
`R8000.ttf`, which carry reply data to the game as character widths. Those files are created by `Install-Nib.ps1`
as placeholders and rewritten by the helper. See `tools/font-transport.mjs`.
