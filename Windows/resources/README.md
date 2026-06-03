# Windows Resources

Place the following files here for the NSIS installer:

- `doumi.ico` — Application icon (convert from `doumi.svg` using ImageMagick:  
  `magick doumi.svg -define icon:auto-resize=256,128,64,48,32,16 doumi.ico`)
- `doumi.svg` — Source SVG icon

If no .ico is available, the NSIS installer will still work but won't
show a custom icon.
