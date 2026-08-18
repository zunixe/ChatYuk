import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../providers/locale_provider.dart';
import '../services/screen_secure_service.dart';
import '../providers/theme_provider.dart';

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
    // Halaman donasi perlu screenshot untuk share QRIS — selalu diizinkan
    ScreenSecureService.enterDonation();
  }

  @override
  void dispose() {
    _tab.dispose();
    // Kembalikan setting global setelah keluar halaman donasi
    ScreenSecureService.exitDonation();
    super.dispose();
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label${context.read<LocaleProvider>().s.msgCopied}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    return Scaffold(
      appBar: AppBar(
          title: Text(s.titleDonate),
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: AppText.bodyStrong.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
          tabs: [
            Tab(text: s.labelQris),
            Tab(text: s.labelUsdt),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _QrisTab(onCopy: _copy),
          _UsdtTab(networks: _networks, onCopy: _copy, s: s),
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
    final s = context.watch<LocaleProvider>().s;
    return SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 8),
          // Nama merchant
          Text(
            'OneHeart',
            textAlign: TextAlign.center,
            style: AppText.title,
          ),
          SizedBox(height: 4),
          Text(
            'NMID: ID1026566504126A01',
            textAlign: TextAlign.center,
            style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
          SizedBox(height: 4),
          Text(
            s.donateScanQris,
            textAlign: TextAlign.center,
            style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 20),
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
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
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/qris_crop.png',
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _InfoCard(
            icon: Icons.info_outline,
            text: s.donateQrisInfo,
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
  final S s;
  const _UsdtTab({required this.networks, required this.onCopy, required this.s});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 8),
          Text(
            s.donateSelectHint,
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 20),
          ...networks.map((n) => _NetworkCard(network: n, onCopy: onCopy, s: s)),
          const SizedBox(height: 16),
          _InfoCard(
            icon: Icons.warning_amber_rounded,
            text: s.donateWrongNetwork,
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
  final S s;
  const _NetworkCard({required this.network, required this.onCopy, required this.s});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: network.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(network.icon, color: network.color, size: 20),
                ),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'USDT ${network.label}',
                      style: AppText.bodyStrong.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      network.subtitle,
                      style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.bgInput,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      network.address,
                      style: AppText.bodySmall.copyWith(
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => onCopy(network.address, '${s.donateCopyAddress}${network.label}'),
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
                label: Text('${s.btnCopyAddress}${network.label}'),
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
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.primary),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
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
    final s = context.read<LocaleProvider>().s;
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withValues(alpha: 0.1),
            AppTheme.primary.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.favorite, color: AppTheme.primary, size: 28),
          SizedBox(height: 8),
          Text(
            s.donateThankYou,
            style: AppText.titleEmphasis,
          ),
          SizedBox(height: 4),
          Text(
            s.donateThanksMsg,
            textAlign: TextAlign.center,
            style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
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
