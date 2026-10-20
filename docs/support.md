# Support · Podpora

**ondrej.linek@gmail.com** — bug reports, questions, and feature requests.
Bugs and ideas are welcome as an issue at
<https://github.com/ondrej-li/vdv-live/issues> as well.

Napište na **ondrej.linek@gmail.com** — chyby, dotazy i nápady. Chyby a nápady
můžete zadat i jako issue na <https://github.com/ondrej-li/vdv-live/issues>.

## English

### A line is missing from the map

The app shows what the regional feed publishes. The feed goes quiet about whole
lines for stretches of the day, and when it does, the line is not on the map.

If you have downloaded the timetables (Settings → Timetables) and switched on
*Fill in lines the feed leaves out*, the app draws lines the timetable says should
be running even when the feed reports nothing. Those markers are drawn as a
**dashed amber capsule with an exclamation triangle**, at the stop the service is
due at. That position is the published stop, not a measurement, so it does not
move and cannot be selected.

### What the exclamation triangle means

Exactly that: the position was calculated from the timetable and the shipped stop
positions, not received from the vehicle. It is a place the bus should be, not a
place it was seen.

### Timetables are not available

Settings → Timetables downloads an index (a couple of megabytes) and then each
line's timetable on demand, a few kilobytes at a time; everything is kept on the
phone afterwards, so it works offline. If a line still says its timetable is not
available, the published archive has been rebuilt and the app's line list is out
of date — the update appears with the next release.

### The map goes grey

Grey markers mean the app has not heard from those vehicles since it last
refreshed — usually a lost connection. The header says `Offline · last 12:34` when
the feed cannot be reached. A position from an hour ago is not the map, so it is
drawn grey rather than passed off as current.

### Reporting a bug

Useful in a report:

- what you expected and what happened;
- the line number and, if the app shows one, the service number;
- the time it happened;
- iOS version and whether it was the phone or the watch;
- a screenshot if it is something you can see.

## Čeština

### Na mapě chybí linka

Aplikace zobrazuje to, co zveřejňuje krajský zdroj dat. Ten občas na část dne
přestane hlásit celé linky, a ty pak na mapě nejsou.

Pokud máte stažené jízdní řády (Nastavení → Jízdní řády) a zapnutou volbu
*Doplnit linky, které zdroj vynechává*, aplikace dokreslí linky, které mají podle
jízdního řádu jet, i když zdroj nehlásí nic. Takové značky mají **oranžový
přerušovaný rámeček a trojúhelník s vykřičníkem** a stojí na zastávce, kde má spoj
právě být. Je to zveřejněná zastávka, ne změřená poloha — značka se neposouvá
a nelze ji vybrat.

### Co znamená trojúhelník s vykřičníkem

Přesně to, co říká: poloha je vypočítaná z jízdního řádu a z poloh zastávek, které
aplikace zná, nikoli přijatá z vozidla. Je to místo, kde autobus má být, ne kde byl
viděn.

### Jízdní řády nejsou k dispozici

Nastavení → Jízdní řády stáhne index (několik megabajtů) a potom jízdní řád
každé linky zvlášť, po několika kilobajtech; vše zůstává v telefonu, takže to pak
funguje i bez sítě. Pokud u linky i tak stojí, že jízdní řád není k dispozici,
znamená to, že zveřejněný archiv byl přestavěn a seznam linek v aplikaci je
zastaralý — oprava přijde s dalším vydáním.

### Mapa zešedne

Šedé značky znamenají, že o těchto vozidlech aplikace od poslední aktualizace
neslyšela — obvykle ztracené připojení. Když se zdroj nedá vůbec načíst, v hlavičce
stojí `Bez připojení · naposledy 12:34`. Poloha stará hodinu není mapa, proto se
kreslí šedě a nevydává se za aktuální.

### Hlášení chyby

V hlášení pomůže:

- co jste čekali a co se stalo;
- číslo linky a případně spoje;
- kdy se to stalo;
- verze iOS a zda šlo o telefon nebo hodinky;
- snímek obrazovky, pokud je chyba vidět.

## Data and attribution

Positions come from the regional map of the Vysočina Region at
mapavdv.kr-vysocina.cz. Timetables come from *Jízdní řády veřejné linkové
dopravy*, published by the Ministry of Transport of the Czech Republic on
portal.cisjr.cz under CC BY 4.0. Stop positions are matched from OpenStreetMap
(© OpenStreetMap contributors, ODbL 1.0). The base map is Apple Maps. The same
credits are in the app, under Settings → Acknowledgements.
