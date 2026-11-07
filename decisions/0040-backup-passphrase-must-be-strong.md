# 0040. A backup passphrase must be strong, not merely long enough

Status: Accepted

Nothing about the backup file format, the key derivation or the recovery key changes. It tightens the rule that decides which passphrase Set Up Backup accepts (ADR 0010).

## Context
The backup's key is random and is wrapped by the passphrase with PBKDF2-SHA256 at 600,000 rounds. The wrapped key sits in the backup file, in a folder (iCloud Drive, Dropbox, a NAS) that anyone with access to the folder can copy, so a person who guesses passphrases offline is the attacker. The rule accepted ten characters with few other conditions: `abcdefghij`, `mypassword1` and `qwertyuiop` passed. PBKDF2 slows each guess down; it does not make a guessable passphrase safe, and it is not memory-hard.

## Decision
- **Twelve characters at least** (`PassphraseStrength.minimumLength`).
- **Weak, whatever the length:** a common word or name inside one of its words (not across the gap between two), more than four characters in a row that each follow the last (`abcde`, `54321`), fewer than eight different characters, or four or more words of which half or more are repeats.
- **Only `strong` is accepted** (`isAcceptable`): four or more words, or twenty characters, or fourteen with three kinds of character. `fair` no longer turns the backup on; the message says four unrelated words work well, or use a recovery key, which needs no passphrase and stays the way to avoid the question.
- This is a floor, not an estimate: `i am a big dog!` passes. A person who wants more uses a recovery key.
- No breached-password list and no network lookup: the rule is local and small on purpose.

## Consequences
- A person who typed a fair passphrase before is not asked again: an existing backup keeps its header. Only Set Up and a changed passphrase meet the rule.
- Tested in `PassphraseStrengthTests`.

## Docs affected
- `decisions/README.md`
