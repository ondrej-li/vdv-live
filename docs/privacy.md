# Privacy policy · Zásady ochrany osobních údajů

Effective 21 October 2026 · Účinné od 21. října 2026

VDV Live shows the live positions of buses and trains in the Vysočina Region, and
its published timetables. It is an unofficial app: it is not operated by the
region, by the Ministry of Transport, or by any transport operator.

VDV Live zobrazuje polohy autobusů a vlaků v Kraji Vysočina a jejich zveřejněné
jízdní řády. Je to neoficiální aplikace: neprovozuje ji kraj, Ministerstvo dopravy
ani žádný dopravce.

## English

### What the app does not do

- No account, no sign-in, no profile.
- No analytics, no advertising, no tracking, no crash reporting.
- No personal data is collected, stored on a server, sold, or shared with anyone.
- The app contains no third-party SDKs.

### What leaves your device

Two public servers are asked for data, the same way a web browser would ask, and
the base map is drawn by Apple's MapKit:

| Server | What is requested | Why |
|---|---|---|
| `mapavdv.kr-vysocina.cz` | the current vehicle positions | the map |
| `portal.cisjr.cz` | the timetable archive's index and individual lines, when you download timetables | stop times, and filling in lines the live feed has dropped |
| Apple (MapKit) | the map tiles, and what MapKit needs to draw them | the base map |

Those servers necessarily see your IP address, the time, and the standard HTTP
request, as any website does. This app adds no identifiers to those requests and
keeps no history of them. The base map is Apple Maps, so Apple sees its own
requests under Apple's privacy policy; the app sends Apple nothing else.

### Your location

The map can open on your position and follow it. That is optional and off unless
you ask for it. The position is read on the device and used only to decide where
the map points. It is never sent anywhere and never written to a log, and it is
not kept anywhere but on this device: the last position it used is remembered so
that the map can open in the right place next time, and it goes when the app does.

### What is kept on your device

Settings, pinned lines, the last positions received (so the map is not empty when
the network is down), and any downloaded timetables are stored inside the app's
own storage. They are not readable by other apps and they go away when you delete
the app.

### Children

The app collects nothing, from anyone.

### Changes

If this policy changes, the new version appears at this address with a new
effective date, and the change is noted in the app's release notes.

### Contact

ondrej.linek@gmail.com

---

## Čeština

### Co aplikace nedělá

- Žádný účet, žádné přihlašování, žádný profil.
- Žádná analytika, reklama, sledování ani hlášení pádů.
- Žádné osobní údaje se neshromažďují, neukládají na server, neprodávají ani
  nepředávají třetím stranám.
- Aplikace neobsahuje žádné SDK třetích stran.

### Co opouští zařízení

Aplikace si vyžádá data ze dvou veřejných serverů, stejně jako by to udělal
webový prohlížeč, a podkladovou mapu kreslí MapKit od Apple:

| Server | Co se požaduje | Proč |
|---|---|---|
| `mapavdv.kr-vysocina.cz` | aktuální polohy vozidel | mapa |
| `portal.cisjr.cz` | index archivu jízdních řádů a jednotlivé linky, pokud si jízdní řády stáhnete | časy zastávek a doplnění linek, které živý zdroj vynechal |
| Apple (MapKit) | dlaždice mapy a to, co MapKit ke kreslení potřebuje | podkladová mapa |

Tyto servery nutně vidí vaši IP adresu, čas a standardní HTTP požadavek, jako
každý jiný web. Aplikace k požadavkům nepřidává žádné identifikátory a historii
požadavků neuchovává. Podkladovou mapou jsou Apple Maps, takže Apple vidí své
vlastní požadavky podle zásad ochrany osobních údajů Applu; nic dalšího mu
aplikace neposílá.

### Vaše poloha

Mapa se může otevřít na vaší poloze a sledovat ji. Je to volitelné a vypnuté,
dokud o to nepožádáte. Poloha se čte v zařízení a slouží jen k určení středu mapy.
Nikam se neposílá a nezapisuje se do logu, a neukládá se nikde jinde než v tomto
zařízení: poslední použitá poloha se pamatuje, aby se mapa příště otevřela na
správném místě, a zmizí spolu s aplikací.

### Co zůstává v zařízení

Nastavení, oblíbené linky, poslední přijaté polohy (aby mapa nezůstala prázdná,
když není síť) a stažené jízdní řády jsou uložené v úložišti aplikace. Jiné
aplikace je nepřečtou a smažou se společně s aplikací.

### Děti

Aplikace neshromažďuje údaje o nikom.

### Změny

Pokud se tyto zásady změní, na této adrese se objeví nová verze s novým datem
účinnosti a změna bude uvedena v poznámkách k vydání.

### Kontakt

ondrej.linek@gmail.com
