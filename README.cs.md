# ImagePG

*[English version](README.md)*

Rychlý nativní prohlížeč a editor obrázků pro macOS 14 a novější. Rozhraní je v angličtině, češtině, slovenštině, němčině, francouzštině, polštině a maďarštině a řídí se jazykem systému; jiný jazyk vyberete v **ImagePG → Nastavení… (⌘,)**. Po změně aplikace nabídne restart. Po otevření zobrazí nejprve menší náhled, plné rozlišení načte na pozadí a připraví náhledy sousedních souborů ve složce.

## Sestavení a spuštění

Na Macu s Xcode spusťte v této složce `./build-app.sh` (s `UNIVERSAL=1` pro Apple Silicon i Intel). Kontroly spustíte `./Tools/run-checks.sh`, archiv pro GitHub Release vytvoří `./Tools/package-release.sh`. Hotová aplikace bude v `dist/ImagePG.app`; lze ji otevřít ve Finderu. Při prvním spuštění může macOS vyžadovat potvrzení otevření lokálně sestavené aplikace.

Systémová ikona je v `Resources/ImagePG.icns`. Její zdrojový obrázek a všechny potřebné velikosti lze znovu vytvořit příkazem `./Tools/build-icon.sh`.

## Ovládání

| Akce | Zkratka |
| --- | --- |
| Nastavení | ⌘, |
| Otevřít obrázek | ⌘O |
| Vložit obrázek ze schránky | ⌘V |
| Uložit / Uložit jako | ⌘S / ⇧⌘S |
| Předchozí / další ve složce | ← / → |
| Otočit doleva / doprava | L / R |
| Změnit velikost | ⌘R |
| Oříznout / výřez | ⌘K |
| Tisk | Ctrl+P nebo ⌘P |
| Velikost plátna | ⇧⌘P |
| Přiblížit / oddálit | ⌘+ / ⌘−, kolečko myši nebo gesto sevření/rozevření na trackpadu |
| Přizpůsobit oknu | ⌘0 |
| Skutečná velikost (100 %) | ⌘1 |

## Tisk

Pomocí **Ctrl+P**, **⌘P** nebo **Soubor → Tisk…** otevřete systémový tiskový dialog s živým náhledem. Lze vybrat tiskárnu, velikost papíru a orientaci na výšku či na šířku. V části **Velikost obrázku** zvolíte přizpůsobení stránce bez ořezu, vyplnění stránky s ořezem nebo vlastní měřítko **0,1–1000 %**. Náhled se aktualizuje i během psaní procent; desetinnou část lze zadat čárkou i tečkou. Při 100 % odpovídá jeden pixel jednomu tiskovému bodu (72 dpi).

Tiskne se jedna stránka s obrázkem uprostřed, s okrajem alespoň 6,35 mm a s ohledem na netisknutelné okraje tiskárny. Přesah při vyplnění stránky nebo velkém vlastním měřítku se ořízne. Tisk zahrnuje aktuální úpravy i neuložené anotace v plném rozlišení; zoom, výběrové úchyty a šachovnicové pozadí se netisknou. Průhledné části mají bílé pozadí. Nabídka **PDF** umožňuje uložit výstup do PDF. Tisk ani jeho zrušení nemění obrázek nebo anotace.

## Zoom a posun

Zoom ovládáte tlačítky − / + v liště, v menu **Zobrazení**, klávesovými zkratkami nebo kolečkem a trackpadem nad fotkou. Při zoomování kolečkem či gestem zůstává bod pod kurzorem na místě, dokud posun nenarazí na okraj fotky. Aktuální procento se zobrazuje v liště i v plovoucím stavovém štítku dole; při zvětšení se používá původní obrázek v plném rozlišení.

Pokud fotka přesahuje zobrazovací plochu, posunete ji podržením levého tlačítka myši a tažením. V panelu anotací nástroj **Výběr** umožňuje posun tažením mimo objekty; s podrženým **mezerníkem** můžete posouvat i přes anotace a při kreslení. Posun končí na okrajích fotky. Nový obrázek se automaticky přizpůsobí oknu. Zoom ani posun nemění uložený obrázek.

## Ořez / výřez

Kliknutím na ikonu ořezu v liště nebo pomocí **⌘K** zapnete výběr výřezu. Tažením myší vyznačte oblast, kterou chcete ponechat. Okolí ztmavne a ve výběru se zobrazí mřížka třetin. Pod výběrem i v plovoucím panelu dole se zobrazuje výsledná šířka a výška v pixelech původního obrázku.

Tažením uvnitř výřez přesunete, rohovými úchyty změníte jeho velikost; tažením mimo výběr vytvoříte nový. **Shift** při kreslení nebo změně velikosti drží čtverec. Zoom funguje i během výběru, s podrženým **mezerníkem** můžete posouvat přiblížený obrázek.

Tlačítkem **Oříznout** nebo klávesou **Enter** použijete výřez v plném rozlišení včetně anotací. Anotace se při tom sloučí s obrázkem. **Esc**, **Zrušit** nebo opětovné kliknutí na ikonu ořezu výběr zruší bez změny obrázku. Oříznutý obrázek uložíte obvyklým **⌘S** nebo **Uložit jako**. Změna velikosti má vlastní ikonu obdélníku s rozměrovými šipkami; velikost plátna používá přerušovaný obdélník.

## Anotace

Kliknutím na ikonu tužky v nástrojové liště otevřete panel **Anotace**. Nástroj vyberete ikonou v horní řadě panelu; panel pak ukazuje jen nastavení daného nástroje a nabízí i paletu rychlých barev. Tužkou, čárou, elipsou a obdélníkem kreslíte tažením; samotné kliknutí těmito nástroji nic nevloží. **Text** vložíte jedním kliknutím na obrázek; jeho obsah a písmo nastavíte v panelu. Panel ukazuje jen nastavení příslušného nástroje. U čáry lze nezávisle nastavit vzhled obou konců. Tloušťku čáry určíte číslem nebo posuvníkem s náhledem. U elipsy a obdélníku podržte při kreslení nebo změně velikosti **Shift** pro kruh či čtverec.

Anotaci vyberete kliknutím. Tažením ji přesunete, úchyty změníte konce čáry nebo rozměry tvaru. V panelu lze kdykoli změnit vlastnosti vybraného objektu; klávesou Delete ho odstraníte. Po uložení se všechny anotace sloučí s obrázkem v jeho plném rozlišení a už nejsou samostatně upravitelné.

Tlačítkem **Kapátko z obrázku** u nastavení barvy a následným kliknutím do obrázku naberete barvu pro aktuální nástroj nebo vybranou anotaci. U obdélníku a elipsy se automaticky zapne výplň a stejná barva se použije i na obrys, takže můžete zakrýt část obrázku barvou okolí. U tužky, čáry a textu se změní barva tahu či textu. Kapátko pracuje s původními pixely i při přiblížení a posunu, zahrnuje již nakreslené anotace a zachovává průhlednost. Po nabrání barvy se vrátíte ke kreslení; bez změny barvy ho zrušíte klávesou **Esc** nebo opětovným stisknutím tlačítka.

Otočení o libovolný úhel je v menu **Úpravy**. Okno si ukládá svou polohu a velikost automaticky. HEIC lze otevírat z Finderu, dialogem **Otevřít** i přetažením, procházet ve složce a upravovat stejně jako ostatní obrázky. Při **Uložit jako** lze vybrat HEIC a nastavit kvalitu komprese nebo obrázek převést například do JPEG či PNG. Formáty se zobrazují podle podpory ImageIO v dané verzi macOS; dostupnost zápisu HEIC/WebP/AVIF se proto může lišit. GIF se nyní zobrazuje jako první snímek a při uložení se uloží jediný snímek.

Obrázek zkopírovaný například z webové stránky vložíte pomocí **⌘V**. Lze ho ihned upravovat a pomocí **⌘S** uložit do nového souboru. Při otevření dalšího obrázku nebo ukončení aplikace se u neuložených změn zobrazí volba uložit, zahodit nebo akci zrušit.
