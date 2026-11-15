import '../../core/text/italian.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/components.dart';
import '../../core/time/measurement_time.dart';
import '../../data/providers.dart';
import '../../data/calendar_summary.dart';
import '../measurements/diary.dart';

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});
  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  late DateTime _selected, _focused;
  @override
  void initState() {
    super.initState();
    final now = ref.read(clockProvider).now();
    _selected = DateTime.utc(now.year, now.month, now.day);
    _focused = _selected;
  }

  void _select(DateTime day) => setState(() {
    _selected = DateTime.utc(day.year, day.month, day.day);
    _focused = _selected;
  });
  Future<void> _jump() async {
    final day = await showDatePicker(
      context: context,
      initialDate: _focused,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (day != null && mounted) _select(day);
  }

  Widget _cell(DateTime day, Map<String, CalendarDaySummary> summaries) {
    final value = summaries[dateKey(day)], selected = isSameDay(day, _selected);
    final label =
        '${countNoun(value?.count ?? 0, 'misurazione', 'misurazioni')}${value?.elevated == true ? ', ${value!.highCount} oltre soglia' : ''}. Mattina ${value?.morning ?? 0}, Pomeriggio ${value?.afternoon ?? 0}, Sera ${value?.evening ?? 0}';
    return Semantics(
      key: ValueKey('calendar-${dateKey(day)}'),
      label: label,
      button: true,
      selected: selected,
      excludeSemantics: true,
      child: GestureDetector(
        excludeFromSemantics: true,
        child: Container(
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 1),
          decoration: BoxDecoration(
            color: selected ? Brand.soft : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? Brand.ink : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (value != null) ...[
                const SizedBox(height: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final band in [
                      value.morning,
                      value.afternoon,
                      value.evening,
                    ].asMap().entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: band.value > 0
                                ? [Brand.blue, Brand.ink, Brand.navy][band.key]
                                : Colors.transparent,
                            shape: band.key == 1
                                ? BoxShape.rectangle
                                : BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${value.count}',
                    style: TextStyle(
                      fontSize: 12,
                      color: value.elevated ? Brand.red : Brand.navy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final month = dateKey(_focused).substring(0, 7);
    final monthly = ref.watch(monthSummaryProvider(month));
    final daily = ref.watch(dayReadingsProvider(dateKey(_selected)));
    final sorted = daily.asData?.value.toList() ?? [];
    sorted.sort((a, b) {
      final band = a.band.index.compareTo(b.band.index);
      if (band != 0) return band;
      final time = a.measuredAtUtc.compareTo(b.measuredAtUtc);
      return time != 0 ? time : a.id.compareTo(b.id);
    });
    return ListView.builder(
      key: const ValueKey('calendar-scroll'),
      padding: const EdgeInsets.all(12),
      itemCount: 1 + (sorted.isEmpty ? 1 : sorted.length),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Calendario',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  TextButton(
                    onPressed: () => _select(ref.read(clockProvider).now()),
                    child: const Text('Oggi'),
                  ),
                  TextButton.icon(
                    onPressed: _jump,
                    icon: const Icon(Icons.event),
                    label: const Text('Scegli mese e anno'),
                  ),
                ],
              ),
              monthly.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) => ErrorFeedback(
                  message: 'Impossibile leggere il mese. Riprova.',
                  onRetry: () => ref.invalidate(monthSummaryProvider(month)),
                ),
                data: (summaries) => TableCalendar<void>(
                  key: const ValueKey('monthly-calendar'),
                  locale: 'it_IT',
                  firstDay: DateTime.utc(1900),
                  lastDay: DateTime.utc(2100, 12, 31),
                  focusedDay: _focused,
                  startingDayOfWeek: StartingDayOfWeek.monday,
                  calendarFormat: CalendarFormat.month,
                  availableGestures: AvailableGestures.horizontalSwipe,
                  availableCalendarFormats: const {
                    CalendarFormat.month: 'Mese',
                  },
                  rowHeight: MediaQuery.textScalerOf(context).scale(1) > 1.5
                      ? 94
                      : 76,
                  daysOfWeekHeight: 32,
                  headerStyle: const HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                  ),
                  onHeaderTapped: (_) => _jump(),
                  calendarStyle: const CalendarStyle(outsideDaysVisible: false),
                  selectedDayPredicate: (d) => isSameDay(d, _selected),
                  onDaySelected: (d, f) => _select(d),
                  onPageChanged: (d) => setState(
                    () => _focused = DateTime.utc(d.year, d.month, d.day),
                  ),
                  calendarBuilders: CalendarBuilders(
                    // CellContent excludes its child semantics in version 3.2.1.
                    // The sibling marker layer keeps the full day description.
                    defaultBuilder: (c, d, f) => const SizedBox.expand(),
                    selectedBuilder: (c, d, f) => const SizedBox.expand(),
                    todayBuilder: (c, d, f) => const SizedBox.expand(),
                    markerBuilder: (c, d, events) =>
                        Positioned.fill(child: _cell(d, summaries)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Indicatori da sinistra: ● Mattina · ■ Pomeriggio · ● Sera. Il numero piccolo indica quante letture contiene il giorno.',
              ),
              const SizedBox(height: 20),
              Text(
                DateFormat('EEEE d MMMM y', 'it_IT').format(_selected),
                key: const ValueKey('selected-calendar-day'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
            ],
          );
        }
        if (daily.hasError) {
          return ErrorFeedback(
            message: 'Impossibile leggere il giorno. Riprova.',
            onRetry: () =>
                ref.invalidate(dayReadingsProvider(dateKey(_selected))),
          );
        }
        if (daily.isLoading && !daily.hasValue) {
          return const Center(child: CircularProgressIndicator());
        }
        if (sorted.isEmpty) {
          return const EmptyState(
            title: 'Nessuna misurazione nel giorno',
            message: 'Seleziona un altro giorno o registra una lettura.',
            icon: Icons.calendar_today_outlined,
          );
        }
        final i = index - 1, m = sorted[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (i == 0 || sorted[i - 1].band != m.band)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: TimeBandBadge(TimeBand.values[m.band.index]),
                ),
              ReadingCard(
                m,
                onOpen: () => context.push('/measurement/${m.id}'),
              ),
            ],
          ),
        );
      },
    );
  }
}
