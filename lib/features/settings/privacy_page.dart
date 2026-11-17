import 'package:flutter/material.dart';
import '../../core/design_system/components.dart';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Privacy e gestione dei dati',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text('Informazioni aggiornate al 16 novembre 2026'),
        const SizedBox(height: 20),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Ambito e sviluppatore",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              SelectableText(
                "CardioGraph è un diario personale offline per Android. Dan King è lo pseudonimo dello sviluppatore e il titolare della firma dell’app. Questa pagina descrive il funzionamento della versione 1.5.2 e i dati gestiti sul dispositivo; non descrive servizi sanitari o piattaforme cloud. Lo sviluppatore non riceve automaticamente il diario e non dispone di un pannello remoto per consultarlo.",
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Dati gestiti e finalità",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              SelectableText(
                "L’app conserva pressione sistolica e diastolica, pulsazioni, note facoltative, date e orari, fuso e offset, origine manuale/fotografica, identificativi tecnici e revisioni. Gestisce inoltre preferenze, orari dei promemoria e data dell’ultimo backup riuscito. Questi dati servono a registrare e correggere le letture, mostrare grafici e calendario, generare report e permettere backup e ripristino. Non viene richiesto un profilo con nome e cognome. L’assenza del nome non rende anonime le informazioni: valori, note e contesto possono comunque identificare una persona e riguardarne la salute.",
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Elaborazione locale e rete",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              SelectableText(
                "Acquisizione, riconoscimento delle cifre, statistiche, PDF e crittografia vengono eseguiti localmente. I font e le risorse necessarie sono inclusi nell’app. La versione Android dichiara INTERNET esclusivamente per controllare in sola lettura le release pubbliche del repository doctorloveapp/cardiograph su api.github.com. Il controllo è attivo di default, disattivabile in Impostazioni → Aggiornamenti, e avviene a ogni avvio senza bloccare il diario se sei offline. Non vengono inviati letture, note, foto, PDF, backup o identificativi del diario. GitHub riceve i normali dati della connessione HTTPS, come indirizzo IP, momento della richiesta e User-Agent generico, secondo la propria informativa (https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement); il controllo di un servizio esterno non è una funzione completamente offline. Non si scaricano né installano APK automaticamente: si apre il browser solo su tua conferma. L’app non integra pubblicità, analisi d’uso, tracciamento o invio automatico di segnalazioni di errore a un server dello sviluppatore. Questo non esclude connessioni autonome del sistema Android, dello store o di altre app, regolate dalle rispettive impostazioni e informative.",
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Fotocamera e file temporanei",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              SelectableText(
                "La fotocamera viene richiesta solo quando scegli di acquisire una foto; puoi usare l’inserimento manuale senza concederla. Le immagini di acquisizione sono temporanee, in memoria/cache privata, e servono al riconoscimento e alla revisione obbligatoria. L’app ne prevede la pulizia a completamento o annullamento e il recupero dei residui al successivo avvio. Anche le copie temporanee dei PDF vengono ripulite. Non è una garanzia di cancellazione forense da ogni supporto o copia esterna.",
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Protezione sul dispositivo",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              SelectableText(
                "Il database locale è cifrato; la chiave è custodita tramite l’archiviazione sicura Android. Il backup automatico e il trasferimento dei dati privati dell’app sono esclusi tramite la configurazione Android. Non è prevista una password obbligatoria per aprire l’app: proteggi quindi il telefono con blocco schermo e aggiornamenti. La cifratura non impedisce l’accesso a chi usa il dispositivo già sbloccato e non garantisce protezione assoluta su dispositivi compromessi. La perdita della chiave locale può rendere il diario illeggibile.",
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Promemoria e permessi",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              SelectableText(
                "Le notifiche sono facoltative. Android gestisce il permesso notifiche, il canale e l’eventuale accesso agli allarmi precisi; senza quest’ultimo la consegna può ritardare. L’app conserva privatamente orari, attivazioni, sessioni già coperte e stato di consegna per evitare avvisi inutili o duplicati. Il testo della notifica non contiene valori di pressione o pulsazioni; la visibilità dipende anche dalle impostazioni del telefono. Non vengono richiesti contatti, posizione, microfono o accesso generale ai file.",
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "PDF, esportazione e condivisione",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              SelectableText(
                "PDF e backup escono dall’area privata solo su tua iniziativa, tramite il selettore file o il pannello di condivisione Android. Scegli tu destinazione e destinatario. Il provider selezionato può essere locale o cloud: da quel momento le sue condizioni e quelle dei destinatari regolano il trattamento delle copie. I PDF non sono protetti da password dall’app e possono contenere letture, note e intestazione facoltativa. Condividi soltanto i dati necessari e controlla l’app scelta prima di confermare.",
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Backup senza o con password",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              SelectableText(
                "Per impostazione iniziale, il file .cardiograph non è cifrato: chi possiede il file può leggerne il contenuto. Il checksum SHA-256 verifica l’integrità, ma non garantisce riservatezza né autenticità contro modifiche intenzionali. Attivando Proteggi backup con password, le esportazioni future vengono cifrate con AES-256-GCM e passphrase derivata tramite Argon2id. La passphrase non viene salvata e non è recuperabile dallo sviluppatore. I vecchi file non vengono cifrati retroattivamente. Il ripristino richiede la password soltanto per un file cifrato.",
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Conservazione, cancellazione e ripristino",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              SelectableText(
                "Le letture restano nel diario finché decidi di conservarle; non è prevista una scadenza automatica. Puoi correggere o eliminare singole letture e usare Backup e dati → Cancella tutti i dati, con doppia conferma. Il ripristino sostituisce esplicitamente letture e preferenze correnti: esporta prima una copia se vuoi conservarle. Cancellare il diario o disinstallare l’app non cancella PDF, backup o copie già salvate, condivise o conservate da terzi: devi gestirle separatamente nei relativi percorsi e servizi.",
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Quadro normativo e diritti",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              SelectableText(
                "Riferimenti: Regolamento (UE) 2016/679 (GDPR) e Codice privacy italiano, d.lgs. 196/2003 e successive modifiche. I dati sulla salute richiedono particolare tutela. L’eccezione per attività esclusivamente personali o domestiche riguarda l’uso individuale, non esonera automaticamente fornitori o usi professionali. Se un soggetto tratta dati altrui deve individuare ruoli, condizioni di liceità e garanzie applicabili. Ove applicabili, i diritti GDPR comprendono accesso, rettifica, cancellazione, limitazione, opposizione e portabilità, secondo i rispettivi presupposti; è possibile rivolgersi al Garante. Nel diario locale consultazione, modifica, export e cancellazione sono disponibili direttamente. La lettura di questa pagina e i permessi Android non costituiscono un consenso generale a ulteriori trattamenti.",
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Collegamenti e assistenza",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              SelectableText(
                "Il pulsante GitHub nella schermata Info apre un’app esterna tramite Android: il sito o il browser possono trattare dati di connessione e usare cookie secondo le loro informative. Repository: https://github.com/doctorloveapp/cardiograph. Le segnalazioni pubbliche sono adatte a quesiti tecnici generici: non pubblicare misurazioni, foto, PDF, backup, password o altri dati personali. Lo sviluppatore non può recuperare o cancellare a distanza un archivio mai ricevuto. Questa pagina non attribuisce allo sviluppatore la gestione di servizi di terzi.",
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Aggiornamenti della pagina",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              SelectableText(
                "Revisione: 16 novembre 2026 · App 1.5.2 (build 9). Le indicazioni descrivono le funzioni implementate e non costituiscono una certificazione di conformità per qualsiasi impiego. Nuovi servizi remoti o finalità richiederebbero una revisione delle informazioni prima della loro introduzione. CardioGraph resta un diario personale e non sostituisce una valutazione medica.",
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fonti ufficiali',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 12),
              SelectableText(
                'GDPR — EUR-Lex\nhttps://eur-lex.europa.eu/eli/reg/2016/679/oj?locale=it\n\nCodice privacy — Normattiva\nhttps://www.normattiva.it/uri-res/N2Ls?urn:nir:stato:decreto.legislativo:2003-06-30;196\n\nGarante per la protezione dei dati personali\nhttps://www.garanteprivacy.it',
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
