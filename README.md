<div align="center">
  <img src="assets/logo.png" alt="CardioGraph" width="112" />
  <h1>CardioGraph</h1>
  <p>Diario pressorio locale per Android.</p>
  <a href="pubspec.yaml"><img alt="Versione" src="https://img.shields.io/badge/versione-1.1.0-1261C9?style=flat-square" /></a>
  <a href="#prerequisiti"><img alt="Android API 26+" src="https://img.shields.io/badge/Android-8.0%2B%20(API%2026%2B)-08D8BF?style=flat-square&logo=android&logoColor=white" /></a>
  <a href="https://flutter.dev/"><img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.38.5-02569B?style=flat-square&logo=flutter" /></a>
  <img alt="Sviluppatore" src="https://img.shields.io/badge/sviluppatore-Dan%20King-142D4E?style=flat-square" />
  <img alt="Offline First" src="https://img.shields.io/badge/stato-Offline--First-006D62?style=flat-square" />
</div>

## Il progetto

CardioGraph è un diario Flutter per Android dedicato a pressione e pulsazioni, senza account o servizi remoti. La versione 1.1.0 include archivio cifrato, acquisizione fotografica con revisione, consultazione, report PDF e backup portabili. Il primo avvio parte senza dati dimostrativi. Il manifest release non richiede accesso a Internet; i badge di questa pagina sono risorse esterne del solo README.

## Funzionalità

| Funzione | Stato |
| --- | --- |
| Archivio Drift/sqlite3mc cifrato, inserimento manuale e CRUD | Disponibile |
| CameraX e OCR a sette segmenti con revisione obbligatoria | Disponibile; regressione locale 6/6 foto, validazione sul campo da estendere |
| Grafici, statistiche e calendario italiano | Disponibili sui dati reali |
| Report PDF offline multipagina, anteprima e SAF | Disponibili; autore PDF vuoto |
| Promemoria locali 10:00 / 16:00 / 21:00 | Disponibili; Doze breve, riavvio e cambio ora/fuso verificati su emulatore |
| Backup .cardiograph e ripristino con sostituzione atomica | Disponibili, standard senza password o cifrati su scelta dell’utente |
| Glass/3D, footer con selezione bianca, modalità opaca persistente | Disponibili |

Dan King identifica lo sviluppatore e il titolare della firma Android; non viene inserito come autore nei report PDF.

## Backup e ripristino

In Impostazioni, **Proteggi backup con password** è disattivato di default. Il backup standard è leggibile da chi possiede il file; SHA-256 rileva la corruzione accidentale e non autentica modifiche intenzionali. La protezione facoltativa cifra le esportazioni future con AES-256-GCM e Argon2id (64 MiB, 3 iterazioni, parallelismo 1). Il ripristino chiede la password solo quando il file selezionato è cifrato, indipendentemente dal flag corrente.

Il contenitore UTF-8 ha un oggetto `header` con `magic=CardioGraphBackup`, `formatVersion=1`, versione app, creazione UTC e `protection=none|aes256gcm`. Nel ramo standard, il checksum SHA-256 in base64 copre la serializzazione canonica di `{header,payload}`: chiavi ordinate, interi, stringhe JSON UTF-8 e nessuno spazio aggiunto. Nel ramo cifrato, la stessa intestazione canonica è AAD; salt casuale 16 byte, nonce 12 byte, tag 16 byte, ciphertext base64. I parametri KDF importati devono corrispondere esattamente al profilo supportato.

Il payload schema 2 contiene letture complete e preferenze portabili. Lo schema 1 è migrato in staging aggiungendo nota vuota, istante originale nullo e modalità opaca false quando assenti. Versioni future, chiavi duplicate, campi sconosciuti, ID duplicati, date incoerenti e parametri abusivi vengono rifiutati. Limiti: **64 MiB e 100.000 letture**, senza esportazione parziale. Chiavi locali, fotografie, PDF, permessi e allarmi Android non entrano nel backup.

Il restore sostituisce esplicitamente l’archivio; non effettua merge. Staging e copia di recupero verificata sono conservati temporaneamente in tabelle del database locale cifrato. Letture, preferenze e marcatore di commit cambiano in un’unica transazione. Un errore prima del commit causa rollback; dopo il commit un errore Android lascia i dati ripristinati e una riconciliazione promemoria da riprovare. **Cancella tutti i dati** è un comando distinto, con proposta di backup e doppia conferma.

## Identità visiva

| Colore | Token | Impiego |
| --- | --- | --- |
| Bianco / bianco azzurrato | #FFFFFF / #F4F9FD | Superfici e sfondo |
| Blu | #1261C9 | Azioni e navigazione |
| Azzurro | #78C8EE | Accenti |
| Verde acqua medicale | #08D8BF | Identità del logo |
| Verde soft / ink | #E5FAF5 / #006D62 | Superfici e testi ad alto contrasto |
| Blu notte | #142D4E | Testo e valori |
| Rosso | #B42338 | Singoli valori sopra soglia e CTA di acquisizione |

Superfici glass con sfondo calibrato, riflessi e ombre stratificate, footer azzurrato con selezione bianca e alternativa opaca persistente; numeri tabulari, semantica accessibile e azioni con dimensioni minime 48 dp. Il logo originale è conservato senza deformazioni.

## Architettura

```text
lib/
  app/                     # avvio, router, provider
  core/design_system/      # tema, token, componenti condivisi
  core/services/           # clock e contratti della piattaforma
  data/                    # Drift, migrazioni conservative, repository e coda scritture
  features/                # measurements, analytics, calendar, reports, reminders, backup
```

Riverpod gestisce dipendenze e preferenze persistite; go_router mantiene le quattro destinazioni tramite StatefulShellRoute. Il clock è iniettabile e le API native sono separate attraverso contratti. Le operazioni crittografiche e la serializzazione pesante usano isolate. Il prototipo tecnico in `fase0/` è archiviato e non è il progetto principale.

## Prerequisiti

- Flutter **3.38.5**, Dart **3.10.4**.
- JDK **21.0.8** per la toolchain validata, bytecode Java/Kotlin 17.
- Android SDK **36**, Build Tools **36.0.0**, NDK **28.2.13676358**.
- Gradle wrapper **8.14**, AGP **8.13.1**, Kotlin Android **2.2.20**.
- Android **8.0 / API 26+**; dispositivo collegato con debug USB per prove fisiche.

Le versioni sono derivate dal lock della Fase 0. Le sole eccezioni per abilitare flutter_localizations con questo SDK sono `intl 0.20.2` e `table_calendar 3.2.1`; nessun dependency override.

## Build essenziale

Dalla radice, su questo ambiente Windows:

```powershell
& 'C:\Users\hp_wi\Downloads\GEMINI~1\flutter\bin\flutter.bat' pub get --enforce-lockfile
& 'C:\Users\hp_wi\Downloads\GEMINI~1\flutter\bin\flutter.bat' analyze
& 'C:\Users\hp_wi\Downloads\GEMINI~1\flutter\bin\flutter.bat' test
& 'C:\Users\hp_wi\Downloads\GEMINI~1\flutter\bin\flutter.bat' build apk --release --target-platform android-arm64 --obfuscate --split-debug-info=output/symbols/1.1.0+2
```

Il percorso breve evita il problema Windows dei native hooks con spazi. Su altre macchine configurare uno SDK compatibile e un percorso locale adeguato; non versionare local.properties.

### Firma release

Application ID e namespace: **dev.danking.cardiograph**. La configurazione legge `secrets/android/key.properties`, con `storeFile`, `storePassword`, `keyAlias` e `keyPassword`. Keystore e credenziali restano esclusi da Git. La release usa il certificato Dan King già impiegato negli aggiornamenti; conservare la stessa chiave per mantenere la continuità delle installazioni. Nessun ripiego sulla firma debug.

Versione Android: **1.1.0 (build 2)**. Artefatto finale: **APK arm64 offuscata**, `build/app/outputs/flutter-apk/app-release.apk`. Conservare separatamente i simboli in `output/symbols/1.1.0+2` per `flutter symbolize`; non incorporarli nell’APK. Per verificarlo usare `apksigner verify --verbose --print-certs` degli Android Build Tools.

## Verifica e limiti noti

Versione **1.1.0+2**, solo arm64. Analisi statica pulita e **68 test Flutter** superati, inclusi OCR locale 6/6, migrazioni, perdita chiave, backup e rollback. Installazione pulita su emulatore Android 16/API 36; aggiornamenti sul Samsung S23 Android 17/API 37 senza cancellare le misurazioni. Backup cifrato provato dalla UI su dati sintetici; PDF verificato anche in Adobe Acrobat. TalkBack collegato e testo 200% verificati; audit vocale umano esteso ancora da completare.

Stress isolato in profile con 10.000/50.000 letture: query mensile p95 **11,7/258,7 ms**, Home da widget montato con DB aperto **1,28 s**, Argon2id+AES per due letture **794 ms** sull’emulatore Windows con GPU host. Non sono misure di avvio a freddo o prestazioni sul telefono minimo. SwiftShader ha provocato crash del processo QEMU; il test è terminato con GPU host. Il budget frame ≥95% a 60 Hz resta da validare su hardware reale di riferimento.

Promemoria verificati su emulatore con Doze breve, reboot senza aprire l’app, cambio ora/fuso e revoca precisione. Restano da estendere durata e matrice produttori. L’OCR richiede sempre revisione manuale: sei foto note non garantiscono affidabilità su altri misuratori o condizioni. PDF limitati a 10.000 letture per documento; backup a 64 MiB/100.000 letture.

## Installazione e manutenzione

Per aggiornare un’installazione esistente usare `adb install -r build/app/outputs/flutter-apk/app-release.apk`, con lo stesso applicationId e certificato. Non disinstallare né cancellare i dati; creare prima un backup portabile. L’installazione pulita è riservata a un emulatore o dispositivo senza dati da conservare.

Conservare privatamente keystore, credenziali e simboli Dart in `output/symbols/1.1.0+2`; archiviare anche il mapping R8 della stessa build. Per un errore dopo il rilascio preferire un aggiornamento correttivo con versionCode superiore e migrazione compatibile. Il downgrade non è una procedura di recupero garantita; il ripristino del diario richiede un backup valido e conferma sostitutiva. Nessun AAB viene prodotto per questa consegna.

Il riferimento operativo è [piano_fasi.md](piano_fasi.md), con prove effettive e verifiche ancora aperte.
