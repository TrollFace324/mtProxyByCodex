# Security

Do not publish server passwords, SSH private keys, generated secrets, or provider tokens in this repository.

If a VPS password has been shared in chat, issue tracker, commits, or logs, rotate it on the server provider side as soon as possible.

Recommended baseline:

- Disable SSH password login after adding an SSH key.
- Keep the proxy secret private unless you intentionally share access.
- Keep only the selected MTProxy TCP port open to the public internet.
- Re-run `install.sh` periodically to update `mtg`.
