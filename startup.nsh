@echo -off

echo [1/2] Searching and executing NVPermissiveEFI...
for %i in fs0 fs1 fs2 fs3 fs4 fs5
  if exist %i:\NVPermissiveEFI.efi then
    %i:\NVPermissiveEFI.efi windows
  endif
endfor

echo [2/2] Searching and booting Windows Boot Manager...
for %i in fs0 fs1 fs2 fs3 fs4 fs5
  if exist %i:\EFI\Microsoft\Boot\bootmgfw.efi then
    echo Found Windows on %i:! Booting now...
    %i:\EFI\Microsoft\Boot\bootmgfw.efi
  endif
endfor
