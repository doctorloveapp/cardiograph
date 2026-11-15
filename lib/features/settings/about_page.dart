import 'package:flutter/material.dart';
import '../../app/version.dart';
import '../../core/design_system/components.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Informazioni & Guida')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: const [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppVersion.label,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 12),
              Text('Sviluppatore: Dan King'),
              Text(
                'Diario personale offline, senza account. I dati restano sul dispositivo; vengono esportati solo su tua richiesta.',
              ),
            ],
          ),
        ),
        SizedBox(height: 24),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Guida breve',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 16),
              Text(
                'Misurazioni',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Premi + e scegli Foto o Manuale. Inquadra i tre valori, evita i riflessi e tocca per mettere a fuoco. Controlla sempre massima, minima, pulsazioni e orario nella revisione prima di salvare. Se necessario regola il ritaglio o inserisci i valori a mano.',
              ),
              SizedBox(height: 16),
              Text(
                'Diario, Andamento e Calendario',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Apri una lettura per modificarla o eliminarla. I grafici separano pressione e pulsazioni; filtra per periodo e fascia. Le letture prima delle 07:00 appartengono alla fascia Sera ma restano nel loro giorno civile.',
              ),
              SizedBox(height: 16),
              Text('Promemoria', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                'In Impostazioni attiva separatamente 10:00, 16:00 e 21:00. Consenti le notifiche e controlla il canale Android. Senza accesso agli allarmi precisi possono arrivare in ritardo. Una lettura non disattiva il promemoria. Il tocco sulla notifica apre la scelta Foto/Manuale.',
              ),
              SizedBox(height: 16),
              Text('Report PDF', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                'Scegli giorno, settimana, mese o intervallo e un’eventuale intestazione. Conferma il riepilogo, controlla l’anteprima e salva con il selettore Android oppure condividi. Il documento non attribuisce la paternità delle letture allo sviluppatore.',
              ),
              SizedBox(height: 16),
              Text(
                'Backup .cardiograph',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Il backup standard non richiede password ed è leggibile da chi possiede il file. Attiva Proteggi backup con password per cifrare le esportazioni future e conserva la password: non è recuperabile dall’app. Il ripristino chiede la password solo se il file selezionato è cifrato.',
              ),
              SizedBox(height: 16),
              Text(
                'Ripristino e cancellazione',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Il ripristino sostituisce letture e preferenze portabili: controlla conteggio e date ed esporta prima una copia dell’archivio attuale. Cancella tutti i dati è un comando distinto con doppia conferma; i file già esportati restano nei percorsi scelti.',
              ),
              SizedBox(height: 16),
              Text(
                'Leggibilità',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Attiva Riduci trasparenze per superfici opache. Il rosso sui singoli numeri indica valori superiori ai riferimenti 135/90 mmHg e 100 bpm; il diario non sostituisce la valutazione del medico.',
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
