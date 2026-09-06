# CC0 Music Archive

Звичайний статичний сайт GitHub Pages для публікації готових музичних треків під CC0 1.0 Universal.

У проєкті немає Jekyll, Ruby, Bundler, npm, build step, backend або бази даних. GitHub Pages може віддавати ці файли напряму.

## Як додати новий трек

Нормальна модель релізу:

1. Підготувати MP3 для прослуховування.
2. Підготувати ZIP з окремими доріжками.
3. За бажанням додати повний біт у цей самий ZIP.
4. Запустити:

```sh
./track.sh add
```

`./add-track.sh` залишений як сумісний короткий alias для `./track.sh add`.

5. Вказати файли й метадані.
6. Скрипт сам:
   - призначить ID;
   - скопіює файли;
   - порахує SHA-256;
   - перевірить і захешує вміст ZIP;
   - оновить `data/tracks.json`;
   - оновить `data/cc0-registry.json`.

Окремий WAV-файл повного біта не є обов’язковим. Якщо потрібно поширювати готовий повний біт разом зі stems, його можна додати безпосередньо до ZIP-архіву.

Скрипт запитує назву, BPM, тональність, тривалість, MP3 для прослуховування, обов’язковий STEMS ZIP, опційний текст, дату публікації, номер реєстру та опційну обкладинку. Перед змінами він показує підсумок і просить підтвердження.

Скрипт не робить commit і не пушить зміни.

Вимоги до CLI: Bash, `python3` зі standard library, `cp`, `mktemp`, `date` та `sha256sum` або `shasum`. Сторонні Python packages, `jq`, npm або build tools не потрібні.

## Structure

```text
/
├── index.html
├── license.html
├── faq.html
├── about.html
├── tracks/
│   └── index.html
├── data/
│   ├── tracks.json
│   └── cc0-registry.json
├── legal/
│   ├── CC0-REGISTRY-TEMPLATE.txt
│   └── README.md
└── assets/
    ├── audio/
    ├── css/
    │   └── app.css
    ├── images/
    └── js/
        └── app.js
```

Файл `.nojekyll` залишений у корені, щоб GitHub Pages обробляв репозиторій як plain static files.

## Local Preview

Запусти будь-який простий static server з кореня репозиторію:

```sh
python3 -m http.server 8000
```

Потім відкрий `http://localhost:8000/`.

Відкрити `index.html` напряму можна, але архів треків використовує `fetch()` для `data/tracks.json`, тому локальний сервер надійніший.

## Data Schema

`data/tracks.json` є єдиним джерелом UI-метаданих для треків. SHA-256 не дублюються тут, бо канонічне джерело provenance і хешів — `data/cc0-registry.json`.

Приклад нового запису:

```json
{
  "id": "BEAT-0007",
  "title": "Скелет з кісток",
  "slug": "skelet-z-kistok",
  "current_version": 2,
  "bpm": 92,
  "key": "D minor",
  "duration": "02:37",
  "published": "2026-09-06",
  "updated": "2026-10-12",
  "registry": "001",
  "source": "suno",
  "preview": "assets/audio/BEAT-0007-v002-skelet-z-kistok-preview.mp3",
  "stems": "assets/audio/BEAT-0007-v002-skelet-z-kistok-stems.zip",
  "full_mix": null,
  "lyrics_id": "LYR-0004"
}
```

`full_mix` є опційним полем для випадку, коли окремий готовий мікс справді опублікований у проєкті поза ZIP. Для звичайного нового релізу достатньо `preview` і `stems`.

## CC0 Registry Schema

`data/cc0-registry.json` фіксує публічний реєстр і точні фізичні файли релізу.

Один логічний музичний матеріал має один ID на кшталт `BEAT-0007`. Preview MP3 і STEMS ZIP є файлами цього самого матеріалу, а не окремими BEAT ID.

Типовий запис з версіями:

```json
{
  "id": "BEAT-0007",
  "title": "Скелет з кісток",
  "type": "suno_generated_audio",
  "origin_label": "AI-generated with Suno",
  "public_url": "tracks/?id=skelet-z-kistok",
  "current_version": 2,
  "versions": [
    {
      "version": 2,
      "release_date": "2026-10-12",
      "note": "Додано трубу та змінено outro",
      "files": [
        {
          "format": "MP3",
          "role": "preview",
          "path": "assets/audio/BEAT-0007-v002-skelet-z-kistok-preview.mp3",
          "sha256": ""
        },
        {
          "format": "STEMS",
          "container": "ZIP",
          "role": "source_package",
          "description": "Окремі доріжки / stems",
          "path": "assets/audio/BEAT-0007-v002-skelet-z-kistok-stems.zip",
          "sha256": "",
          "contents": [
            {
              "file": "bass.wav",
              "format": "WAV",
              "sha256": ""
            }
          ]
        }
      ]
    }
  ]
}
```

Не вигадуй SHA-256. Якщо файл ще не фінальний, не публікуй фіктивний хеш.

## Як оновити існуючий трек

```sh
./track.sh update BEAT-0007
```

Під час оновлення:

- ID треку не змінюється;
- створюється нова версія;
- стара версія не видаляється;
- старі SHA-256 залишаються в реєстрі;
- сайт автоматично починає показувати нову версію;
- стару версію можна перевірити через сторінку CC0.

Приклад:

```text
BEAT-0007 v1
→ первинний реліз

BEAT-0007 v2
→ дописана/оновлена версія
```

Файли нових версій отримують immutable filenames:

```text
assets/audio/BEAT-0007-v002-skelet-z-kistok-preview.mp3
assets/audio/BEAT-0007-v002-skelet-z-kistok-stems.zip
```

Опубліковані раніше URL не перейменовуються лише заради нового формату назв.

## Чому хеші всередині ZIP важливі

Реєстр зберігає два рівні перевірки:

- SHA-256 самого ZIP-архіву;
- SHA-256 кожного regular file всередині архіву.

Це дозволяє людині витягнути, наприклад, `full_mix.wav` і перевірити, що саме цей файл був частиною опублікованого CC0-релізу, навіть якщо оригінального ZIP більше немає під рукою.

Скрипт не розпаковує архів у публічну директорію. Він читає ZIP, відхиляє пошкоджені архіви, абсолютні шляхи, `../` та нерегулярні записи, а потім сортує список вмісту детерміновано.

## Lyrics

Текст пісні залишається окремим матеріалом з власним ID, наприклад `LYR-0004`, бо походження тексту може відрізнятися від походження музики.

Для lyrics скрипт вимагає явне підтвердження, що це оригінальний текст, створений видавцем. Це формулювання не застосовується до Suno-generated audio.

## Images

Компактний візуальний ідентифікатор сайту: `assets/images/site-artwork.jpg`. Зберігай його оригінальне співвідношення сторін. Якщо filename зміниться, онови посилання в HTML/JSON/JS.

## Audio Files

MP3 preview і STEMS ZIP зберігаються в `assets/audio/`, щоб GitHub Pages міг віддавати їх напряму.

GitHub має обмеження на розмір репозиторіїв і файлів. Перед завантаженням великих архівів перевір актуальні ліміти GitHub Pages/GitHub.

## Licensing Wording

Сайт каже, що треки “опубліковані під CC0”. Suno, якщо релевантно, згадується лише як технічна інформація про походження музичного матеріалу або інструменталу, а не як головна тема сайту.

CC0 застосовується лише до авторських і суміжних прав, які видавець юридично має право передати або від яких має право відмовитися. CC0 не надає прав третіх сторін.

## Future Formal Declaration

Чернетка декларації опублікована в `declaration.html`. Формальну декларацію, підписані manifests, КЕП/e-signature files, notarial files або lawyer-reviewed documents варто додавати в `legal/` тільки після реального юридичного ревʼю та підписання.
