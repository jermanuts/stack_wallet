import 'package:decimal/decimal.dart';
import 'package:mockito/annotations.dart';
import 'package:stackwallet/services/locale_service.dart';
import 'package:stackwallet/services/wallets.dart';
import 'package:stackwallet/themes/theme_service.dart';
import 'package:stackwallet/utilities/amount/amount.dart';

/// quick amount constructor wrapper. Using an int is bad practice but for
/// testing with small amounts this should be fine
Amount _a(int i) => Amount.fromDecimal(
      Decimal.fromInt(i),
      fractionDigits: 8,
    );

@GenerateMocks([
  Wallets,
  LocaleService,
  ThemeService,
])
void main() {
  // testWidgets('test widget loads correctly', (widgetTester) async {
  //   final CoinServiceAPI wallet = MockBitcoinWallet();
  //   final mockThemeService = MockThemeService();
  //
  //   mockito.when(mockThemeService.getTheme(themeId: "light")).thenAnswer(
  //         (_) => StackTheme.fromJson(
  //           json: lightThemeJsonMap,
  //         ),
  //       );
  //   mockito.when(wallet.walletId).thenAnswer((realInvocation) => "wallet id");
  //   mockito.when(wallet.coin).thenAnswer((realInvocation) => Coin.bitcoin);
  //   mockito
  //       .when(wallet.walletName)
  //       .thenAnswer((realInvocation) => "wallet name");
  //   mockito.when(wallet.balance).thenAnswer(
  //         (_) => Balance(
  //           total: _a(0),
  //           spendable: _a(0),
  //           blockedTotal: _a(0),
  //           pendingSpendable: _a(0),
  //         ),
  //       );
  //
  //   final wallets = MockWallets();
  //   final wallet = Manager(wallet);
  //
  //   mockito.when(wallets.getManagerProvider("wallet id")).thenAnswer(
  //       (realInvocation) => ChangeNotifierProvider((ref) => manager));
  //
  //   const walletSheetCard = SimpleWalletCard(
  //     walletId: "wallet id",
  //   );
  //
  //   await widgetTester.pumpWidget(
  //     ProviderScope(
  //       overrides: [
  //         pWallets.overrideWithValue(wallets),
  //         pThemeService.overrideWithValue(mockThemeService),
  //         coinIconProvider.overrideWithProvider(
  //           (argument) => Provider<String>((_) =>
  //               "${Directory.current.path}/test/sample_data/light/assets/dummy.svg"),
  //         ),
  //       ],
  //       child: MaterialApp(
  //         theme: ThemeData(
  //           extensions: [
  //             StackColors.fromStackColorTheme(
  //               StackTheme.fromJson(
  //                 json: lightThemeJsonMap,
  //               ),
  //             ),
  //           ],
  //         ),
  //         home: const Material(
  //           child: walletSheetCard,
  //         ),
  //       ),
  //     ),
  //   );
  //
  //   await widgetTester.pumpAndSettle();
  //
  //   expect(find.byWidget(walletSheetCard), findsOneWidget);
  // });
}
