import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';

class DonateScreen extends StatefulWidget {
  const DonateScreen({super.key});

  @override
  State<DonateScreen> createState() => _DonateScreenState();
}

class _DonateScreenState extends State<DonateScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;

  static const _networks = [
    _UsdtNetwork(
      label: 'TRC20',
      subtitle: 'Tron Network',
      icon: Icons.toll,
      address: 'TRGo2h1FcFK2X9gcE333ndrkhz2gZTDt3Q',
      color: Color(0xFFE53935),
    ),
    _UsdtNetwork(
      label: 'ERC20',
      subtitle: 'Ethereum Network',
      icon: Icons.hexagon_outlined,
      address: '0x87b2e5bc728c8ff4b96140415bc15989fa2a6504',
      color: Color(0xFF5C6BC0),
    ),
    _UsdtNetwork(
      label: 'BEP20',
      subtitle: 'BNB Smart Chain',
      icon: Icons.currency_exchange,
      address: '0x87b2e5bc728c8ff4b96140415bc15989fa2a6504',
      color: Color(0xFFF9A825),
    ),
    _UsdtNetwork(
      label: 'Morph',
      subtitle: 'Morph L2',
      icon: Icons.bolt_outlined,
      address: '0x87b2e5bc728c8ff4b96140415bc15989fa2a6504',
      color: Color(0xFF7C4DFF),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label disalin ke clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Donasi'),
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          tabs: const [
            Tab(text: 'QRIS'),
            Tab(text: 'USDT Crypto'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _QrisTab(onCopy: _copy),
          _UsdtTab(networks: _networks, onCopy: _copy),
        ],
      ),
    );
  }
}

class _QrisTab extends StatelessWidget {
  final void Function(String text, String label) onCopy;
  const _QrisTab({required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Text(
            'Scan QRIS di bawah untuk donasi',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 24),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.primary, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_2, size: 120, color: AppTheme.textSecondary),
                  SizedBox(height: 8),
                  Text(
                    'QR Code akan segera\nditambahkan',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          _InfoCard(
            icon: Icons.info_outline,
            text: 'QRIS dapat digunakan di semua aplikasi dompet digital dan mobile banking Indonesia (GoPay, OVO, Dana, BCA, Mandiri, dll)',
          ),
          const SizedBox(height: 16),
          _ThankYouNote(),
        ],
      ),
    );
  }
}

class _UsdtTab extends StatelessWidget {
  final List<_UsdtNetwork> networks;
  final void Function(String text, String label) onCopy;
  const _UsdtTab({required this.networks, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Text(
            'Pilih network dan salin alamat wallet',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 20),
          ...networks.map((n) => _NetworkCard(network: n, onCopy: onCopy)),
          const SizedBox(height: 16),
          _InfoCard(
            icon: Icons.warning_amber_rounded,
            text: 'Pastikan kamu mengirim ke network yang benar. Mengirim ke network yang salah dapat menyebabkan dana hilang.',
          ),
          const SizedBox(height: 16),
          _ThankYouNote(),
        ],
      ),
    );
  }
}

class _NetworkCard extends StatelessWidget {
  final _UsdtNetwork network;
  final void Function(String, String) onCopy;
  const _NetworkCard({required this.network, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: network.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(network.icon, color: network.color, size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'USDT ${network.label}',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      network.subtitle,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      network.address,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: AppTheme.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => onCopy(network.address, 'Alamat ${network.label}'),
                    child: const Icon(Icons.copy, size: 18, color: AppTheme.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => onCopy(network.address, 'Alamat ${network.label}'),
                icon: const Icon(Icons.copy, size: 16),
                label: Text('Salin Alamat ${network.label}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: network.color,
                  side: BorderSide(color: network.color),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoCard({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThankYouNote extends StatelessWidget {
  const _ThankYouNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withValues(alpha: 0.1),
            AppTheme.primary.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        children: [
          Icon(Icons.favorite, color: AppTheme.primary, size: 28),
          SizedBox(height: 8),
          Text(
            'Terima Kasih!',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Donasi kamu membantu pengembangan ChatYuk agar terus gratis dan bebas iklan.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _UsdtNetwork {
  final String label;
  final String subtitle;
  final IconData icon;
  final String address;
  final Color color;
  const _UsdtNetwork({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.address,
    required this.color,
  });
}
