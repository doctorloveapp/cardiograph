<div align="center">
  <img src="assets/logo.png" alt="CardioGraph" width="112" />
  <h1>CardioGraph</h1>
  <p>Il tuo diario della pressione. Personale, leggibile, sempre con te.</p>
  <a href="pubspec.yaml"><img alt="Versione" src="https://img.shields.io/badge/versione-0.1.0--dev-1261C9?style=flat-square" /></a>
  <a href="#prerequisiti"><img alt="Android API 26+" src="https://img.shields.io/badge/Android-8.0%2B%20(API%2026%2B)-08D8BF?style=flat-square&logo=android&logoColor=white" /></a>
  <a href="https://flutter.dev/"><img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.38.5-02569B?style=flat-square&logo=flutter" /></a>
  <img alt="Sviluppatore" src="https://img.shields.io/badge/sviluppatore-Dan%20King-142D4E?style=flat-square" />
  <img alt="Offline First" src="https://img.shields.io/badge/stato-Offline--First-006D62?style=flat-square" />
</div>

## Il progetto

CardioGraph è un diario Flutter per Android dedicato a pressione e pulsazioni, senza account o servizi remoti. La versione 0.1.0-dev implementa le fondamenta navigabili: le schermate partono vuote, senza letture inventate. Il manifest release non richiede accesso a Internet; i badge di questa pagina sono risorse esterne del solo README.

## Funzionalità

| Disponibile | In sviluppo nelle fasi successive |
| --- | --- |
| Home, Andamento, Calendario, Report e Impostazioni | Archivio cifrato e inserimento delle letture |
| Scelta foto/manuale e percorsi dedicati | OCR a sette segmenti con conferma obbligatoria |
| Design system e modalità opaca | Grafici, calendario mensile e PDF |
| Icone adattive e splash dal logo ufficiale | Promemoria 10:00/16:00/21:00 e backup/restore |

I backup saranno senza password per impostazione predefinita; la protezione sarà una scelta facoltativa. Dan King identifica lo sviluppatore e il titolare della firma Android: non è un autore da inserire nei report PDF del diario.

## Identità visiva

| Colore | Token | Impiego |
| --- | --- | --- |
| Bianco / bianco azzurrato | #FFFFFF / #F4F9FD | Superfici e sfondo |
| Blu | #1261C9 | Azioni e navigazione |
| Azzurro | #78C8EE | Accenti |
| Verde acqua medicale | #08D8BF | Identità del logo |
| Verde soft / ink | #E5FAF5 / #006D62 | Superfici e testi ad alto contrasto |
| Blu notte | #142D4E | Testo e valori |
| Rosso | #B42338 | Errori e superamenti delle soglie |

Superfici glass con blur confinato e alternativa opaca; numeri tabulari, semantica accessibile e azioni con dimensioni minime 48 dp. Il logo originale è conservato senza deformazioni.

## Architettura

```text
lib/
  app/                     # avvio, router, provider
  core/design_system/      # tema, token, componenti condivisi
  core/services/           # clock e contratti della piattaforma
  features/                # schermate e percorsi per funzionalità
```

Riverpod gestisce dipendenze e preferenze della sessione; go_router mantiene le quattro destinazioni tramite StatefulShellRoute. Il clock è iniettabile e le API native sono separate attraverso contratti. I servizi non ancora implementati non producono risultati simulati. Il prototipo tecnico in `fase0/` è archiviato e non è il progetto principale.

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
& 'C:\Users\hp_wi\Downloads\GEMINI~1\flutter\bin\flutter.bat' build apk --release --no-pub --target-platform android-arm64,android-x64
```

Il percorso breve evita il problema Windows dei native hooks con spazi. Su altre macchine configurare uno SDK compatibile e un percorso locale adeguato; non versionare local.properties.

### Firma release

Application ID e namespace: **dev.danking.cardiograph**. La configurazione legge `secrets/android/key.properties`, con `storeFile`, `storePassword`, `keyAlias` e `keyPassword`. Keystore e credenziali restano esclusi da Git. La release usa il certificato Dan King già disponibile per le prove; la chiave definitiva di distribuzione va gestita nel rilascio. Nessun ripiego sulla firma debug.

APK: `build/app/outputs/flutter-apk/app-release.apk`. Per verificarlo usare `apksigner verify --verbose --print-certs` degli Android Build Tools.

## Avanzamento

Il riferimento operativo è [piano_fasi.md](piano_fasi.md): aggiornare le caselle soltanto dopo verifiche effettive. Il progetto non dichiara ancora completate persistenza, lettura fotografica, report clinici o notifiche.
