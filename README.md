Where do these files come from?
|||
|-------------|----------------------------------------------------------|
| bootx64.efi | from ubuntu server iso /EFI/boot/bootx64.efi             |
| initrd      | from ubuntu server iso /casper/initrd                    |
| unicode.pf2 | from ubuntu server iso /boot/grub/fonts/unicode.pf2      |
| vmlinuz     | from ubuntu server iso /casper/vmlinuz                   |
| grubx64.efi | extracted from `grub-efi-amd64-signed_*ubuntu*amd64.deb` |

.
.
ATTENTION!
Download `deb` archives and extract files from them _ *on the same hardware architecture* _ that the clients will be booting from.
E.g. note that `grubx64.efi` is a renamed `grubnetx64.efi.signed` from a `*_amd64.deb` package
