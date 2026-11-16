# App Store listing, version 1.4.2

Everything the product page needs, written to be pasted into App Store Connect.
Character counts are measured against Apple's limits, and the Czech copy is the
primary language - English is the second localization, if one is enabled.

The build this describes is **1.4.2** - 1.3 was the widgets and the timetable
repair, 1.4 added sharing, and 1.4.2 is the timetable release: delays that belong
to the service they were measured for, a mapping that repairs itself after every
republication of the archive, and screens that let the downloaded timetables be
read. The newest build number is on `make check-release`. `docs/ship.md` covers the
upload itself; the privacy and support URLs are the ones hosted from
`docs/privacy.md` and `docs/support.md`.

## Czech (primary)

### Název (30 znaků)

```
VDV Live
```

### Podtitul (30 znaků)

```
Živá mapa autobusů Vysočiny
```

### Propagační text (170 znaků)

Dá se změnit kdykoli bez nového review.

```
Novinka ve verzi 1.4.2: zpoždění u správného spoje, jízdní řády, které se samy opraví po každém zveřejnění archivu, a procházení stažených linek.
```

### Klíčová slova (100 znaků, bez mezer za čárkami)

```
autobus,vlak,jízdní řád,odjezdy,zastávka,mapa,Vysočina,Třebíč,Jihlava,Žďár,doprava,spoj
```

### Popis (4000 znaků)

```
VDV Live ukazuje, kde právě jedou autobusy a vlaky v Kraji Vysočina – na jedné mapě, bez účtu a bez reklam.

ŽIVÁ MAPA KRAJE
Každé vozidlo, které kraj hlásí, je na mapě jako bod obarvený podle zpoždění: zeleně do pěti minut, oranžově do deseti, červeně nad deset, šedě když zdroj zpoždění neuvádí. Mapa je zamčená na Vysočinu, takže se nedá odjet mimo kraj. Vozidla se mezi obnoveními plynule posouvají a ta, o kterých zdroj na chvíli zmlkne, zůstanou na místě zešedlá.

OBLÍBENÉ LINKY
Připněte si linky, které jezdíte, hvězdičkou na kartě vozidla nebo v seznamu linek. Přepínač Oblíbené pak nechá na mapě jen je – a volba si pamatuje i příští spuštění.

ODJEZDOVÁ TABULE ZASTÁVKY
Klepněte na zastávku a uvidíte, co odsud jede: linku, cíl, čas podle jízdního řádu a očekávaný čas podle skutečného zpoždění. Tabule se dá omezit na oblíbené linky a posouvat dál do dne.

OFICIÁLNÍ JÍZDNÍ ŘÁDY
Stáhněte jednou index jízdních řádů Ministerstva dopravy a karta vozidla ukáže všechny zastávky spoje s časy posunutými o zpoždění, které zdroj hlásí. Řády se stahují po linkách a zůstávají v telefonu, takže fungují i bez sítě. Zapněte Doplnit linky, které zdroj vynechává, a aplikace dokreslí spoj tam, kde má podle řádu být.

UPOZORNĚNÍ PŘED ODJEZDEM
Zvolte spoj, zastávku a jak dlouho předem chcete vědět. Upozornění respektuje dny, kdy spoj jede, státní svátky i konec platnosti řádu.

SDÍLENÍ
Pošlete odkaz na spoj s jeho polohou a zpožděním, nebo na odjezdovou tabuli zastávky. Odkaz se otevře přímo v aplikaci – na stejném spoji nebo zastávce.

WIDGETY NA PLOCHU
Odjezdová tabule zvolené zastávky: u každého odjezdu linka, cíl, čas a stav – včas, +3 min, nebo zatím jen podle řádu. Widget oblíbených spojů ukáže nejbližší vozidla vašich linek a dá se nastavit na zastávku, kolem které se má dívat, nebo nechat na vaší poloze. Oba widgety mají malou, střední i velkou velikost na iPhonu i iPadu a data si stahují samy.

APPLE WATCH
Vozidla oblíbených linek na zápěstí, obarvená podle zpoždění. Hodinky si data stahují samy, takže telefon nemusí být po ruce.

FUNGUJE I OFFLINE
Když síť vypadne, mapa nezůstane prázdná: poslední načtená data zůstanou na obrazovce zešedlá, dokud nepřijde čerstvá odpověď.

SOUKROMÍ
Bez účtu, bez reklam, bez analytiky a bez sledování. Aplikace neshromažďuje žádné osobní údaje a poloha zůstává v zařízení.

ZDROJE DAT
Polohy vozidel pocházejí z veřejné mapy Kraje Vysočina, jízdní řády z archivu Ministerstva dopravy (CC BY 4.0) a podkladovou mapu kreslí Apple Maps. Zdroje jsou uvedené přímo v aplikaci. VDV Live je neoficiální aplikace a není spojená s krajem ani s dopravci.
```

### Co je nového (4000 znaků)

```
ZPOŽDĚNÍ U SPRÁVNÉHO SPOJE

• Odjezdová tabule bere zpoždění z konkrétního spoje, ne z celé linky. Neukáže tak zpoždění autobusu, který jede opačným směrem nebo už dojel na konec.
• Hodnoty se obnovují při každém načtení, takže tabule nezůstane viset na čísle z rána.

JÍZDNÍ ŘÁDY, KTERÉ SE OPRAVÍ SAMY

• Archiv ministerstva se zveřejňuje několikrát týdne a pokaždé přečísluje položky. Aplikace to pozná, stáhne si nové mapování linek a místo „linka není ve zveřejněném jízdním řádu“ u všeho načte řády dál.
• Když ministerstvo vydá linku v několika obdobích platnosti, použije se to, které platí dnes.

CO JE STAŽENÉ

• Po stažení indexu se ukáže přehled: kolik linek, z jakého zveřejnění a kolik jich už je v telefonu – s odkazem na procházení.
• Stažené linky se dají číst: trasa, dopravce, platnost, spoje se zastávkami a zdrojové tabulky tak, jak je ministerstvo zveřejnilo.
• Diagnostika ukáže i každý soubor na disku, linku, kterou hlásí, a linku, která ho čte.

Také v této verzi: sdílení spojů a tabulí, widgety na plochu a hodinky vydrží bez telefonu.
```

## English

### Name (30 characters)

```
VDV Live
```

### Subtitle (30 characters)

```
Live bus and train map
```

### Promotional text (170 characters)

```
New in 1.4.2: delays that belong to your own service, timetables that repair themselves after every archive publication, and a browser for what was downloaded.
```

### Keywords (100 characters, no spaces after commas)

```
bus,train,timetable,departures,stop,map,Vysocina,Czechia,transit,live,delay
```

### Description (4000 characters)

```
VDV Live shows where the buses and trains of the Vysocina Region are right now - on one map, with no account and no ads.

A LIVE MAP OF THE REGION
Every vehicle the region reports is a dot coloured by how late it is: green up to five minutes, amber to ten, red beyond, grey when the feed does not say. The camera is locked to Vysocina, so the map cannot wander off. Vehicles glide between refreshes, and one the feed goes quiet about stays where it was, greyed out.

PINNED LINES
Pin the lines you travel on, from a vehicle's card or from the line list. The Pinned filter then leaves only those on the map - and remembers the choice next time.

A STOP'S DEPARTURE BOARD
Tap a stop to see what leaves it: line, destination, the timetable's time and the expected one, moved by the live delay. Narrow the board to your pinned lines, or read on into the evening.

OFFICIAL TIMETABLES
Download the Ministry of Transport's timetable index once, and a vehicle's card lists every stop of its run with the times the delay actually makes them. Lines are fetched one at a time and kept on the phone, so they work offline. Lines the feed has gone quiet about can be filled in from their timetables too.

DEPARTURE REMINDERS
Pick a service, a stop and how early you want to know. Reminders follow the days the service runs, public holidays, and the end of the timetable's validity.

SHARING
Send a link to a vehicle with its position and delay, or to a stop's departure board. The link opens in the app, on that same vehicle or board.

HOME SCREEN WIDGETS
A departure board for the stop you choose: every row has the line, where it goes, when it leaves and how it stands - on time, three minutes late, or still just the timetable's time. The starred traffic widget lists the nearest vehicles of your pinned lines, and can be pointed at a stop or left on your own position. Both come in small, medium and large, on iPhone and iPad, and fetch their own data.

APPLE WATCH
Your pinned lines' vehicles on your wrist, coloured by delay. The watch fetches its own data, so the phone does not have to be nearby.

WORKS OFFLINE
When the network drops, the map does not empty: the last payload stays on screen, greyed, until a live answer replaces it.

PRIVACY
No account, no ads, no analytics, no tracking. The app collects no personal data, and your position stays on the device.

WHERE THE DATA COMES FROM
Vehicle positions come from the region's public map, timetables from the Ministry of Transport's archive (CC BY 4.0), and the base map is drawn by Apple Maps. Every source is named inside the app. VDV Live is unofficial and not affiliated with the region or with any operator.
```

### What's New (4000 characters)

```
DELAYS THAT BELONG TO YOUR SERVICE

• A stop's board takes each delay from the run it was measured for, not from the line as a whole. It no longer shows the lateness of a bus going the other way, or of one that has finished and is standing at the terminus.
• The numbers follow the feed, so a board does not stay stuck on the value it had this morning.

TIMETABLES THAT REPAIR THEMSELVES

• The ministry's archive is republished several times a week and renumbers every entry when it is. The app notices, fetches a fresh line mapping, and carries on instead of answering "not in the published timetable" for every line at once.
• Where a line is published for several validity periods, the one in force today is the one used.

WHAT WAS DOWNLOADED

• After the index downloads, a summary says how many lines arrived, which publication they are from, and how many are already on the phone - with a way into them.
• The downloaded lines can be read: route, operator, validity, the runs with their stops, and the source tables exactly as the ministry published them.
• Diagnostics names every file on disk, the line it declares and the line that reads it.

Also in this release: sharing vehicles and boards, home screen widgets, and the watch app working without the phone.
```

## Screenshots

Files live in `screenshots/` and `make screenshots` regenerates them from a clean
simulator (`screenshots/README.md` has the details). App Store Connect takes them
tab by tab; this is the order worth using, because the first two are the ones most
people see in search:

| # | iPhone 6.3" (1206 x 2622) | iPad 13" (2064 x 2752) | Frame |
|---|---|---|---|
| 1 | `iphone/01-main.png` | `ipad/01-main.png` | The live map, with pinned lines marked |
| 2 | `iphone/04-departure-board.png` | `ipad/04-departure-board.png` | A stop's board: line, destination, expected time |
| 3 | `iphone/03-service-timetable.png` | `ipad/03-service-timetable.png` | A service's stops, moved by the live delay |
| 4 | `iphone/02-settings.png` | `ipad/02-settings.png` | Settings and the timetable download |

The Apple Watch tab takes `screenshots/watch/01-main.png` and `02-service.png`
(422 x 514, Apple Watch Ultra 49 mm).

If the frames are given captions later, these read well against them and use the
app's own words:

| # | Czech | English |
|---|---|---|
| 1 | Živá mapa kraje | The region, live |
| 2 | Odjezdy z vaší zastávky | Departures from your stop |
| 3 | Jízdní řády i se zpožděním | Timetables with live delays |
| 4 | Vše, co potřebujete, v nastavení | Everything else, in Settings |

The widgets are not in this set: App Store screenshots have to be the app's own
screen at a device size, and a widget lives on the home screen. If a widget frame
is wanted, capture it on a device or a simulator with the widget placed - touch and
hold the home screen, add both widgets, then take a normal device screenshot at the
sizes above. WidgetKit renders the extension itself, so the frame is the real thing
rather than a mockup.

## Review notes

Paste into *App Store Review Information → Notes*:

```
No account or sign-in is needed. Vehicle positions come from the Vysocina Region's public map (mapavdv.kr-vysocina.cz), timetables from the Ministry of Transport's archive (portal.cisjr.cz), the line-to-entry mapping from the project's own static site (vdv.ondralinek.cz), and the base map is Apple Maps. They are attributed in Settings -> Acknowledgements.

The app collects nothing; there is no analytics and no tracking.

The home screen widgets read what the app already knows - pinned lines, starred stops, the last position and the downloaded timetables - from an App Group shared with the extension. To try the departure board widget, touch and hold it on the home screen, choose Edit Widget and pick a stop; a stop is not required for the app itself. The starred traffic widget needs a position, which the app records when it next takes a fix.

The amber exclamation badge on the map marks a line the live feed has stopped reporting but whose timetable says should be running; it is not an error state.
```

## Checklist before submitting

- [ ] Version 1.4.2, with the newest build selected on the version page
- [ ] Promotional text, description, keywords and What's New pasted for Czech
- [ ] English localization filled in, if enabled
- [ ] iPhone 6.3" and iPad 13" screenshot tabs filled (four each, in the order above)
- [ ] Apple Watch tab filled, if the watch app is listed with the iOS app
- [ ] Privacy policy `https://vdv.ondralinek.cz/privacy.html`, support `https://vdv.ondralinek.cz/support.html`
- [ ] App Privacy still says **Data Not Collected** (the widgets add no collection)
- [ ] Review notes pasted
