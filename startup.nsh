@echo -off

echo ============================================================
echo NVPermissive Compat - diagnostic boot (v2)
echo ============================================================
echo.
echo [0/3] GPU inventory - look for rows with vendor 10DE (NVIDIA):
pci
echo.

echo [1/3] Searching and executing NVPermissiveCompat...
for %i in fs0 fs1 fs2 fs3 fs4 fs5 fs6 fs7
  if exist %i:\NVPermissiveCompat.efi then
    %i:\NVPermissiveCompat.efi windows
  endif
endfor

echo [2/3] Searching legacy NVPermissiveEFI...
for %i in fs0 fs1 fs2 fs3 fs4 fs5 fs6 fs7
  if exist %i:\NVPermissiveEFI.efi then
    %i:\NVPermissiveEFI.efi windows
  endif
endfor

echo [3/3] Searching and booting Windows Boot Manager...
for %i in fs0 fs1 fs2 fs3 fs4 fs5 fs6 fs7
  if exist %i:\EFI\Microsoft\Boot\bootmgfw.efi then
    echo Found Windows on %i:! Booting now...
    %i:\EFI\Microsoft\Boot\bootmgfw.efi
  endif
endfor
