// DemoTestScreen — sabit konum + sabit varış + sabit raporlar ile rota
// karşılaştırmasını tek tıkla gösteren video çekimi modu.
//
// Akış: /demo → "Testi Başlat" → /route/detail (RouteRequest sabit).
// Seed raporları (assets/seed_reports.json) ilk açılışta yüklendiği için
// yolu kapsayan ihbar kümeleri zaten DB'de. Buna ek olarak ana yolun
// göbeğine deterministik bir "chokepoint" ihbar kümesi inject ediyoruz —
// böylece en güvenli rota dolanmak zorunda kalıyor ve gözle görülür şekilde
// uzuyor.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';

import '../../app/real_providers.dart';
import '../../core/geohash.dart';
import '../../data/local_db.dart';
import '../route/route_planner_screen.dart' show RouteRequest;

/// Demoda kullanılan sabit başlangıç noktası — Dolmabahçe / Beşiktaş
/// sahil aksının başı. Çırağan chokepoint koridorunun güney ucu.
const LatLng kDemoOrigin = LatLng(41.0425, 29.0085);

/// Demoda kullanılan sabit varış noktası — Ortaköy yakını. Çırağan
/// chokepoint koridorunun kuzey ucu — bu iki noktayı birleştiren doğru
/// chokepoint cluster'ının tam üzerinden geçer.
const LatLng kDemoDestination = LatLng(41.0580, 29.0185);

/// Ana yolun göbeğinde, en kısa rotanın doğal olarak geçtiği koridora
/// inject ettiğimiz yüksek riskli ihbar kümesi. Stabil ID'ler sayesinde
/// /demo'ya her girişte aynı satırlar — duplicate yok.
///
/// Koordinatlar `kDemoOrigin` → `kDemoDestination` doğrusunun ÜSTÜNE
/// yerleştirildi (5 nokta, eşit aralıklı). Böylece en kısa rotanın
/// kullandığı edge'lerin geohash7 cell'leri kesin olarak chokepoint
/// cell'leriyle örtüşür. Her chokepoint cluster halinde 8 rapor (seeder
/// `clusterCount` kadar satır yazar) — cell base risk skoru tek raporluk
/// chokepoint'e kıyasla ~8 kat fazla, rerank'in alternatif yolu seçme
/// motivasyonu garanti.
const List<_DemoChokepoint> _kDemoChokepoints = [
  _DemoChokepoint(
    id: 'demo-chokepoint-1',
    text: 'Sahil yolunda silahlı saldırı oldu, polis bölgede.',
    title: 'Silahlı saldırı',
    location: 'Dolmabahçe çıkışı',
    category: 'violence',
    riskLevel: 'high',
    severity: 'Yüksek',
    point: LatLng(41.0455, 29.0105),
    clusterCount: 8,
  ),
  _DemoChokepoint(
    id: 'demo-chokepoint-2',
    text: 'Bıçaklı kavga, ambulans çağrıldı, çevre güvenli değil.',
    title: 'Bıçaklı kavga',
    location: 'Çırağan (alt)',
    category: 'violence',
    riskLevel: 'high',
    severity: 'Yüksek',
    point: LatLng(41.0485, 29.0125),
    clusterCount: 8,
  ),
  _DemoChokepoint(
    id: 'demo-chokepoint-3',
    text: 'Yayalar gasp edildi, telefonlar ve cüzdanlar alındı.',
    title: 'Gasp',
    location: 'Çırağan (orta)',
    category: 'theft',
    riskLevel: 'high',
    severity: 'Yüksek',
    point: LatLng(41.0510, 29.0140),
    clusterCount: 8,
  ),
  _DemoChokepoint(
    id: 'demo-chokepoint-4',
    text: 'Bir grup yayalara saldırdı, polis müdahale etti.',
    title: 'Fiziksel saldırı',
    location: 'Çırağan (üst)',
    category: 'violence',
    riskLevel: 'high',
    severity: 'Yüksek',
    point: LatLng(41.0535, 29.0155),
    clusterCount: 8,
  ),
  _DemoChokepoint(
    id: 'demo-chokepoint-5',
    text: 'Sözlü taciz ve tehdit, yayalar bölgeden uzak durmalı.',
    title: 'Sokak tacizi',
    location: 'Ortaköy yakını',
    category: 'harassment',
    riskLevel: 'high',
    severity: 'Yüksek',
    point: LatLng(41.0560, 29.0175),
    clusterCount: 8,
  ),
];

/// Demo videosunda yol üzerinde göstereceğimiz örnek ihbarlar. Bu liste
/// seed_reports.json'daki gerçek ihbar kümeleriyle örtüşür + ana koridora
/// inject ettiğimiz chokepoint'leri içerir.
final List<_DemoIncident> _kDemoIncidents = [
  for (final c in _kDemoChokepoints)
    _DemoIncident(
      title: c.title,
      location: c.location,
      severity: c.severity,
      point: c.point,
      isChokepoint: true,
    ),
  const _DemoIncident(
    title: 'Hırsızlık',
    location: 'Beşiktaş İskele',
    severity: 'Yüksek',
    point: LatLng(41.0420, 29.0048),
  ),
  const _DemoIncident(
    title: 'Vandalizm',
    location: 'Çırağan',
    severity: 'Yüksek',
    point: LatLng(41.0535, 29.0165),
  ),
];

class DemoTestScreen extends ConsumerStatefulWidget {
  const DemoTestScreen({super.key});

  @override
  ConsumerState<DemoTestScreen> createState() => _DemoTestScreenState();
}

class _DemoTestScreenState extends ConsumerState<DemoTestScreen> {
  Future<void>? _seedFuture;

  @override
  void initState() {
    super.initState();
    _seedFuture = _ensureChokepointReports(ref);
  }

  Future<void> _onStartPressed() async {
    // Garantiye al: chokepoint inject tamamlanmadan navigate etme.
    try {
      await (_seedFuture ?? _ensureChokepointReports(ref));
    } catch (_) {
      // Sessiz fail — seed yapılamasa bile rota açılsın, gerçek seed
      // (seed_reports.json) yine de yolu kapsıyor.
    }
    if (!mounted) return;
    context.push(
      '/route/detail',
      extra: RouteRequest(
        from: kDemoOrigin,
        to: kDemoDestination,
        time: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Demo Test'),
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildIntroCard(theme)),
          SliverToBoxAdapter(child: _buildMapPreview(theme)),
          SliverToBoxAdapter(child: _buildRoutePointsCard(theme)),
          SliverToBoxAdapter(child: _buildIncidentsCard(theme)),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              textStyle: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            icon: const Icon(Icons.play_arrow_rounded, size: 28),
            label: const Text('Testi Başlat'),
            onPressed: _onStartPressed,
          ),
        ),
      ),
    );
  }

  Widget _buildIntroCard(ThemeData theme) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Card(
        color: cs.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.science_outlined, color: cs.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sabit Senaryo',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: cs.onSecondaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Başlangıç, varış ve yol üzerindeki ihbarlar sabittir. '
                      '"Testi Başlat"a basınca uygulama iki rota önerir: '
                      'gri (en kısa) ve yeşil (en güvenli). Yeşil rota, '
                      'ihbar olan bölgelerden kaçınarak nasıl döndüğünü '
                      'gösterir.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSecondaryContainer,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapPreview(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 220,
          child: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(41.050, 29.013),
              initialZoom: 14,
              interactionOptions: InteractionOptions(
                flags: InteractiveFlag.none,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.evam.saferoute',
              ),
              MarkerLayer(
                markers: [
                  for (final i in _kDemoIncidents)
                    Marker(
                      width: i.isChokepoint ? 36 : 28,
                      height: i.isChokepoint ? 36 : 28,
                      point: i.point,
                      child: i.isChokepoint
                          ? Container(
                              decoration: BoxDecoration(
                                color: Colors.red.shade700,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.block,
                                color: Colors.white,
                                size: 20,
                              ),
                            )
                          : Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.red.shade700,
                              size: 24,
                            ),
                    ),
                  const Marker(
                    width: 40,
                    height: 40,
                    point: kDemoOrigin,
                    child: Icon(Icons.my_location,
                        color: Colors.blue, size: 32),
                  ),
                  const Marker(
                    width: 40,
                    height: 40,
                    point: kDemoDestination,
                    child: Icon(Icons.flag,
                        color: Colors.green, size: 32),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoutePointsCard(ThemeData theme) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _routeRow(
                icon: Icons.my_location,
                iconColor: Colors.blue,
                label: 'Başlangıç',
                value: 'Dolmabahçe / Beşiktaş sahili',
                coords: kDemoOrigin,
                theme: theme,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Container(
                      width: 2,
                      height: 24,
                      color: cs.outlineVariant,
                    ),
                  ],
                ),
              ),
              _routeRow(
                icon: Icons.flag,
                iconColor: Colors.green,
                label: 'Varış',
                value: 'Ortaköy',
                coords: kDemoDestination,
                theme: theme,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _routeRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required LatLng coords,
    required ThemeData theme,
  }) {
    return Row(
      children: [
        Icon(icon, color: iconColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: theme.textTheme.titleMedium,
              ),
              Text(
                '${coords.latitude.toStringAsFixed(4)}, '
                '${coords.longitude.toStringAsFixed(4)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIncidentsCard(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'Rota üzerinde ${_kDemoIncidents.length} ihbar',
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final i in _kDemoIncidents)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i.severity == 'Yüksek'
                              ? Colors.red.shade700
                              : Colors.orange.shade700,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${i.title} — ${i.location}',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      if (i.isChokepoint) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Ana yol',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.deepPurple.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: i.severity == 'Yüksek'
                              ? Colors.red.shade50
                              : Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          i.severity,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: i.severity == 'Yüksek'
                                ? Colors.red.shade900
                                : Colors.orange.shade900,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DemoIncident {
  const _DemoIncident({
    required this.title,
    required this.location,
    required this.severity,
    required this.point,
    this.isChokepoint = false,
  });

  final String title;
  final String location;
  final String severity;
  final LatLng point;

  /// Ana yolu kapatmak için inject edilen ihbar mı? UI'da farklı vurgu.
  final bool isChokepoint;
}

class _DemoChokepoint {
  const _DemoChokepoint({
    required this.id,
    required this.text,
    required this.title,
    required this.location,
    required this.category,
    required this.riskLevel,
    required this.severity,
    required this.point,
    this.clusterCount = 1,
  });

  final String id;
  final String text;
  final String title;
  final String location;
  final String category;
  final String riskLevel;
  final String severity;
  final LatLng point;

  /// Bu chokepoint için inject edilecek rapor sayısı. Yüksek değer → cell
  /// base risk skoru yükselir → routing rerank detour'a daha çok meyilli.
  final int clusterCount;
}

/// Chokepoint raporlarını DB'ye yazar ve etkilenen hücreleri yeniden
/// hesaplar. Her çağrıda önce eski `demo-chokepoint-*` satırlarını silip
/// güncel listeyi inject eder — koordinatlar değiştiğinde eski izler kalmaz.
Future<void> _ensureChokepointReports(WidgetRef ref) async {
  final localDb = ref.read(localDbProvider);
  final db = await localDb.db;
  final uid = ref.read(currentUserUidValueProvider);
  final risk = ref.read(realRiskEngineProvider);
  final now = DateTime.now().toUtc();

  // FK target — seed UID yoksa ekle.
  await db.insert(
    'users',
    {
      'uid': uid,
      'reputation': 1.0,
      'created_at': now.millisecondsSinceEpoch,
    },
    conflictAlgorithm: ConflictAlgorithm.ignore,
  );

  // Eski chokepoint satırlarının hücrelerini de yeniden hesaplamalıyız
  // — silindikten sonra o hücrelerin skoru düşmeli.
  final oldCells = <String>{};
  final oldRows = await db.query(
    'reports',
    columns: ['geohash7'],
    where: "id LIKE 'demo-chokepoint-%'",
  );
  for (final row in oldRows) {
    final gh = row['geohash7'] as String?;
    if (gh != null) oldCells.add(gh);
  }

  await db.delete('reports', where: "id LIKE 'demo-chokepoint-%'");

  final newCells = <String>{};
  for (final c in _kDemoChokepoints) {
    final geohash7 = Geohash.encode(
      c.point.latitude,
      c.point.longitude,
      precision: 7,
    );
    newCells.add(geohash7);

    // Tek chokepoint için `clusterCount` adet rapor yaz — cell base risk
    // doğrudan rapor sayısıyla orantılı (RiskEngine.baseRisk topluyor).
    // Lat/lng aynı kalır, ID'ler farklı olur (-0, -1, ..., -N).
    for (int i = 0; i < c.clusterCount; i++) {
      await db.insert(
        'reports',
        {
          'id': '${c.id}-$i',
          'uid': uid,
          'text': c.text,
          'lat': c.point.latitude,
          'lng': c.point.longitude,
          'geohash7': geohash7,
          'occurred_at': now.millisecondsSinceEpoch,
          'category': c.category,
          'risk_level': c.riskLevel,
          'confidence': 0.95,
          'explanation': 'Demo chokepoint — sabit yüksek riskli ihbar.',
          'status': 'CLASSIFIED',
          'synced': 0,
          'created_at': now.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  for (final cell in {...oldCells, ...newCells}) {
    try {
      await risk.recomputeCell(cell, now);
    } catch (_) {
      // En kötü senaryoda eski hücre skoru kalır — demo yine de çalışır.
    }
  }
}
