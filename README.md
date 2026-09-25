# Wine for RigDesk

The Wine that runs Windows programs inside **[RigDesk](https://rigdesk.app)** on Android
is built here, in the open, from public source.

- **Source:** [`GameNative/wine`](https://github.com/GameNative/wine), branch `wine-11.3` —
  upstream Wine 11.3 plus community patches for Android/bionic.
- **Our changes:** the two patches in [`patches/`](patches) and the build recipe in
  [`.github/workflows/build-wine.yml`](.github/workflows/build-wine.yml) and
  [`scripts/`](scripts). Nothing else is changed.
- **Target:** `x86_64-linux-android28`. box64 translates the x86-64 code to ARM on the phone,
  so no root, no proot and no Linux image are needed.
- **The built layer** that RigDesk downloads is published in
  [`desk-wine-dist`](https://github.com/vankata7pisaka/desk-wine-dist/releases). You can
  build your own from this repository and load it into RigDesk instead.
- **Licence:** Wine is LGPL-2.1. The libraries packed next to it keep their own licences,
  shipped in `licenses/` inside the archive.

Build it yourself: **Actions → Build Wine for Desk → Run workflow** (about 45 minutes on a
GitHub runner).

The notes below are the working log, in Bulgarian.

---

# Desk — билдът на Wine

Тук не се пише Wine. Wine е чужд публичен код под LGPL-2.1, писан от 1993 г.
Тук се прави **билдът за телефона**: наши настройки, наша версия, наш път
вътре, и нищо чуждо двоично не влиза в Desk наготово.

Резултатът е един файл — `wine-x86_64.tar.xz` — който отива в
`E:\Desk\app\src\main\assets\win\` и се разпъва от `core/win/WineContainer.kt`.

## Как се пуска

**Actions → Build Wine for Desk → Run workflow.** Един час на чужд процесор,
нула байта на нашия диск. После артефактът се сваля от същата страница.

## Веригата на телефона

```
  .exe  →  Wine        отговаря на повикванията към Windows
        →  box64       превежда x86_64 инструкциите на ARM
        →  Desk (X11)  рисува прозореца
```

Затова Wine се компилира за `x86_64-linux-android28`, а не за ARM: box64
превежда x86 код, значи Wine ТРЯБВА да е x86 — но свързан с Android libc,
не с glibc. Оттам идва цялата разлика с обикновения Wine за Linux и оттам
идва това, че не трябват нито proot, нито гигабайтов Linux корен.

## Двата компилатора

Wine е две половини и всяка се прави с различен инструмент:

| Половина | С какво | Какво е |
|---|---|---|
| Unix | Android NDK r27d | `.so` файлове, които говорят с Android |
| Windows | llvm-mingw | `.dll` файлове — това, което програмата вижда |

## Какво НЕ иска от X сървъра

Настройката е нарочно без `xrender`, `xshm`, `xcursor`, `xfixes`, `xrandr`,
`xinput2`, `xshape`. Тоест на X сървъра в Desk му стига основният протокол,
който вече говори.

## Откъде идва изходният код

`GameNative/wine` — upstream Wine плюс кръпките за Android/bionic. Кръпките са
работа на общността; без тях Wine не се компилира за телефон изобщо. Ползваме
публичен код и си го компилираме сами — това е разликата от „вземаме чуждото
готово двоично".

Заглавките и част от библиотеките (libX11, freetype) идват от Termux sysroot.
`scripts/pack-for-desk.sh` носи в Desk само онези от тях, които наистина се
отварят — пита всеки изпълним файл какво му трябва, вместо да копира папка.
Лицензите им пътуват в `licenses/` вътре в архива.

## Защо има и наши кръпки — `patches/`

Кръпките за Android в `GameNative/wine` са писани за по-стар Wine и клонът
`wine-11.3` е отбелязан като WIP. Единайсет от тях вече не се лепят, а `git
apply` е „всичко или нищо": провали ли се един хънк, не влиза нито един.
Билд #2 (2026-08-13) умря точно така — кръпката за pulse не влезе,
`PTHREAD_MUTEX_ROBUST` не съществува в bionic, `make` спря, а понеже чуждият
скрипт няма `set -e`, стъпката се отчете като УСПЕШНА и излезе архив от
975 MB само с Windows половината и без нито една unix библиотека.

Затова тук:

- нашите кръпки в `patches/` са направени срещу истинския код на 11.3 и се
  лепят строго — не влязат ли, билдът спира веднага;
- чуждите могат да се провалят, но всяка провалена се изписва по име;
- `make` върви с `-k`, за да излязат всички грешки от един билд, а не по
  една на всеки час;
- след компилирането се проверява, че unix страната наистина съществува.

**Разчита се на размито лепене — не.** `patch --fuzz=3` уж залепва повечето
от изостаналите кръпки, но проверено: в `window.c` то би вкарало `#ifdef`
без затварящ `#endif`, защото Wine 11.3 вече прави същото по друг начин, а в
`signal_x86_64.c` би сложило Android код в напълно чужда функция — кодът,
за който е писана кръпката, изобщо го няма в 11.3.

Пропуснатите чужди кръпки и защо не липсват: XFixes/XInput2 огражданията са
излишни, понеже така или иначе се компилира без тези разширения; GLX е
излишен, понеже X сървърът на Desk няма GLX; `steamuser → xuser` е козметика;
esync/fsync ги няма в 11.3 изобщо.

## Библиотеки, които се отварят по време на работа

`pack-for-desk.sh` тръгва от изпълнимите файлове и пита всеки какво му трябва
(`NEEDED`). Wine обаче отваря част от библиотеките си с `dlopen` — чак когато
наистина потрябват. Тогава името им не стои никъде в ELF таблиците, тъй че
проследяването не ги вижда и те мълчаливо не влизат.

**Измерено на 14.08.2026:** инсталаторът на Steam мина докрай, но самият Steam
остана завинаги на „Checking for available updates…". Причината беше един ред:

```
err:winediag:gnutls_process_attach failed to load libgnutls,
  no support for encryption
```

Тоест Wine беше без НИКАКВО TLS, а всичко в интернет днес е през HTTPS.
Програмата не гърми — тя чака ръкостискане, което няма как да се случи, и
отвън изглежда просто бавна. Затова `RUNTIME_LIBS` в скрипта носи такива
изрично, а липсва ли някоя, билдът спира вместо да пусне тих Wine без TLS.

Отделно: `err:dnsapi:DllMain No libresolv support` остава и не се поправя тук
— в bionic резолверът е вътре в libc и отделна `libresolv` няма. Засяга само
`DnsQuery`, не и обикновеното разрешаване на имена през Winsock.
