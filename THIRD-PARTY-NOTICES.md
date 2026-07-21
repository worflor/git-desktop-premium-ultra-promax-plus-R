# Third-party notices

This file inventories the third-party material bundled in or referenced by
this repository, as identified in [LICENSE.md](LICENSE.md). Third-party
material is not relicensed by the Work Notice; the terms below continue to
apply to it.

## Fonts (`apps/desktop-flutter/assets/fonts/`)

The bundled font files are licensed under the SIL Open Font License,
Version 1.1. The copyright and reserved-font-name notices for each family:

- DM Sans — Copyright 2014 The DM Sans Project Authors
  (https://github.com/googlefonts/dm-fonts)
- JetBrains Mono — Copyright 2020 The JetBrains Mono Project Authors
  (https://github.com/JetBrains/JetBrainsMono)
- Playfair Display — Copyright 2017 The Playfair Display Project Authors
  (https://github.com/clauseggers/Playfair-Display), with Reserved Font Name
  "Playfair Display"
- Lora — Copyright 2011 The Lora Project Authors
  (https://github.com/cyrealtype/Lora-Cyrillic), with Reserved Font Name
  "Lora"
- VT323 — Copyright 2011, The VT323 Project Authors (peter.hull@oikoi.com)

The full text of the SIL Open Font License, Version 1.1 is reproduced at the
end of this file.

## GloVe vectors (`apps/desktop-flutter/assets/engram/glove300.bin`)

`glove300.bin` is a quantized (int16, global scale 6.0) derivative of the
Stanford GloVe-300 pre-trained word vectors.

Jeffrey Pennington, Richard Socher, Christopher D. Manning. "GloVe: Global
Vectors for Word Representation" (2014). https://nlp.stanford.edu/projects/glove/

The pre-trained vectors are made available by their authors under the Open
Data Commons Public Domain Dedication and License v1.0
(https://opendatacommons.org/licenses/pddl/1-0/).

`alexandria.endb` in the same directory is an original Woflo Labs artifact
(semantic wells seeded from GloVe) and is covered by the root Work Notice,
not by this file.

## Flutter

The application is built with the Flutter SDK (BSD-3-Clause), and the
platform runner directories under `apps/desktop-flutter/windows`, `linux`,
and `macos` derive from Flutter's project templates. Binary distributions
embed the Flutter engine and Dart runtime; the license notices for those
components and all Dart packages compiled into a build ship inside the build
as Flutter's generated notices bundle.

## Build-time dependencies

Dart/pub packages (`apps/desktop-flutter/pubspec.yaml`) are not vendored into
this repository. They are fetched at build time and remain under their own
licenses.

---

## SIL Open Font License, Version 1.1

```text
SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007
-----------------------------------------------------------

PREAMBLE
The goals of the Open Font License (OFL) are to stimulate worldwide
development of collaborative font projects, to support the font creation
efforts of academic and linguistic communities, and to provide a free and
open framework in which fonts may be shared and improved in partnership
with others.

The OFL allows the licensed fonts to be used, studied, modified and
redistributed freely as long as they are not sold by themselves. The
fonts, including any derivative works, can be bundled, embedded, 
redistributed and/or sold with any software provided that any reserved
names are not used by derivative works. The fonts and derivatives,
however, cannot be released under any other type of license. The
requirement for fonts to remain under this license does not apply
to any document created using the fonts or their derivatives.

DEFINITIONS
"Font Software" refers to the set of files released by the Copyright
Holder(s) under this license and clearly marked as such. This may
include source files, build scripts and documentation.

"Reserved Font Name" refers to any names specified as such after the
copyright statement(s).

"Original Version" refers to the collection of Font Software components as
distributed by the Copyright Holder(s).

"Modified Version" refers to any derivative made by adding to, deleting,
or substituting -- in part or in whole -- any of the components of the
Original Version, by changing formats or by porting the Font Software to a
new environment.

"Author" refers to any designer, engineer, programmer, technical
writer or other person who contributed to the Font Software.

PERMISSION & CONDITIONS
Permission is hereby granted, free of charge, to any person obtaining
a copy of the Font Software, to use, study, copy, merge, embed, modify,
redistribute, and sell modified and unmodified copies of the Font
Software, subject to the following conditions:

1) Neither the Font Software nor any of its individual components,
in Original or Modified Versions, may be sold by itself.

2) Original or Modified Versions of the Font Software may be bundled,
redistributed and/or sold with any software, provided that each copy
contains the above copyright notice and this license. These can be
included either as stand-alone text files, human-readable headers or
in the appropriate machine-readable metadata fields within text or
binary files as long as those fields can be easily viewed by the user.

3) No Modified Version of the Font Software may use the Reserved Font
Name(s) unless explicit written permission is granted by the corresponding
Copyright Holder. This restriction only applies to the primary font name as
presented to the users.

4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font
Software shall not be used to promote, endorse or advertise any
Modified Version, except to acknowledge the contribution(s) of the
Copyright Holder(s) and the Author(s) or with their explicit written
permission.

5) The Font Software, modified or unmodified, in part or in whole,
must be distributed entirely under this license, and must not be
distributed under any other license. The requirement for fonts to
remain under this license does not apply to any document created
using the Font Software.

TERMINATION
This license becomes null and void if any of the above conditions are
not met.

DISCLAIMER
THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT
OF COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE
COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL
DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM
OTHER DEALINGS IN THE FONT SOFTWARE.
```
