import 'package:flutter/material.dart';
import '../../app/version.dart';
import '../../core/design_system/components.dart';
import '../../core/design_system/theme.dart';
import '../../core/services/platform_services.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Info')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        GlassCard(
          child: Column(
            children: [
              Image.asset(
                'assets/logo.png',
                width: 108,
                height: 108,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),
              Text(
                'CardioGraph',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text('Versione dell’applicazione'),
              const Text(AppVersion.label, textAlign: TextAlign.center),
            ],
          ),
        ),
        const SizedBox(height: 20),
        GlassCard(
          child: LayoutBuilder(
            builder: (context, box) {
              final compact =
                  box.maxWidth < 280 ||
                  MediaQuery.textScalerOf(context).scale(14) > 21;
              final identity = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dan King',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('Flutter & Android Developer'),
                ],
              );
              final link = IconButton.filled(
                key: const ValueKey('repository-link'),
                tooltip: 'Apri repository GitHub nel browser',
                style: IconButton.styleFrom(
                  backgroundColor: Brand.blue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(52, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () async {
                  try {
                    await AndroidDocumentFileService.channel.invokeMethod(
                      'openRepository',
                    );
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Nessun browser disponibile. Riprova.'),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.code),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.asset(
                          'assets/sviluppatore.jpg',
                          width: compact ? 60 : 72,
                          height: compact ? 60 : 72,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 16),
                      if (!compact)
                        Expanded(child: identity)
                      else
                        const Spacer(),
                      link,
                    ],
                  ),
                  if (compact) ...[const SizedBox(height: 16), identity],
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

class GuidePage extends StatelessWidget {
  const GuidePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Guida breve')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: const [
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
                'In Impostazioni → Promemoria attiva le fasce e scegli gli orari (predefiniti 10:00, 16:00 e 21:00). Consenti le notifiche e controlla il canale Android. Senza accesso agli allarmi precisi possono arrivare in ritardo. Il promemoria viene mostrato solo se manca una lettura nella relativa sessione. Una lettura notturna copre la sera precedente. Il tocco sulla notifica apre la scelta Foto/Manuale.',
              ),
              SizedBox(height: 16),
              Text('Report PDF', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                'Scegli giorno, settimana, mese, intervallo o Tutte le misurazioni e un’eventuale intestazione. Conferma il riepilogo, controlla l’anteprima e salva con il selettore Android oppure condividi. Il documento non attribuisce la paternità delle letture allo sviluppatore.',
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
                'Riferimenti',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Il rosso sui singoli numeri indica valori superiori ai riferimenti 135/90 mmHg e 100 bpm; il diario non sostituisce la valutazione del medico.',
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
