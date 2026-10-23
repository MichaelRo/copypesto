# Name, icon and brand

Pesto's source code is released under the [MIT license](LICENSE). That license covers the code. It does not cover the
Pesto name, the logo and app icon (the P mark and the jar illustration), the screenshots and artwork, or the written
copy on copypesto.net. Those stay with the maintainer.

This page says what that means in practice. It is a plain-English policy, not a legal contract.

## Which files that covers
The app icon and its layers (`Sources/Resources/Pesto.icon`, the icon sets in `Sources/Resources/Assets.xcassets` and
`design/source/`), the illustrations in `Sources/Resources/Assets.xcassets`, and the pictures in `docs/images`. If you
fork the app, replace them.

## What you can do

- Use, study, change and redistribute the code under the MIT license.
- Say that you use Pesto, review it, or write about it. Use the name to refer to the real app.
- Link to the project, and use the icon and screenshots to illustrate a review or an article about Pesto.
- Say that your project is based on Pesto's code ("a fork of Pesto"), as long as it is clear that it is a different,
  unofficial project.

## What you should not do

- Give a modified build the name Pesto, or a name or icon so close that people could take it for the official app.
- Distribute a build under the official bundle identifier, or from the official update feed.
- Suggest that the maintainer endorses, supports or is responsible for your build.
- Use the name or icon in a way that implies a product, service or company that does not exist.

## If you fork

A fork needs its own identity. Before you distribute a build, change all of these:

1. **Name and icon.** Pick your own.
2. **Bundle identifier.** The official one is `net.copypesto.pesto`. Use one under a domain you control.
3. **Update feed and key.** Pesto checks `https://copypesto.net/appcast.xml` (`SUFeedURL` in
   `Sources/Resources/Info.plist`) and trusts only updates signed with the official public key (`SUPublicEDKey`). A
   build that keeps both would offer your users the official app, and a build that keeps only the key could install
   official updates over your fork. Set your own feed URL and generate your own key pair with Sparkle's
   `generate_keys`.
4. **Signing identity.** Sign with your own Developer ID, not the maintainer's.
5. **Support and security contacts.** Point to your own, so reports about your build do not reach this project.

## Other uses of the word

Pesto is a free, open-source app. It is not trying to compete with other clipboard managers, and this policy is about
this app, its logo and its icon, nothing wider. "Pesto" is also a food and the name of other products. The maintainer
does not claim the word as an ordinary word and does not object to uses that cannot be mistaken for this app. Pesto is
an independent project and is not affiliated with Pesto Clipboard.

## Questions

Write to hello@copypesto.net if you are unsure whether a use is fine. Asking first is welcome.
