Where do these files come from?

| file        | source                                           |
|-------------|--------------------------------------------------|
| bootx64.efi | ubuntu server iso `/EFI/boot/bootx64.efi`        |
| initrd      | ubuntu server iso `/casper/initrd`               |
| unicode.pf2 | ubuntu server iso `/boot/grub/fonts/unicode.pf2` |
| vmlinuz     | ubuntu server iso `/casper/vmlinuz`              |
| grubx64.efi | `grub-efi-amd64-signed_*ubuntu*amd64.deb`        |

.
.
### ATTENTION!

Download `deb` archives and extract files from them _ *on the same hardware architecture* _ that the clients will be booting from.
E.g. note that `grubx64.efi` is a renamed `grubnetx64.efi.signed` from a `*_amd64.deb` package
