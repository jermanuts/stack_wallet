import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:stackwallet/models/isar/models/isar_models.dart';
import 'package:stackwallet/models/send_view_auto_fill_data.dart';
import 'package:stackwallet/pages/address_book_views/address_book_view.dart';
import 'package:stackwallet/pages/send_view/confirm_transaction_view.dart';
import 'package:stackwallet/pages/send_view/sub_widgets/building_transaction_dialog.dart';
import 'package:stackwallet/pages/send_view/sub_widgets/transaction_fee_selection_sheet.dart';
import 'package:stackwallet/pages/token_view/token_view.dart';
import 'package:stackwallet/providers/providers.dart';
import 'package:stackwallet/providers/ui/fee_rate_type_state_provider.dart';
import 'package:stackwallet/providers/ui/preview_tx_button_state_provider.dart';
import 'package:stackwallet/route_generator.dart';
import 'package:stackwallet/services/coins/manager.dart';
import 'package:stackwallet/utilities/address_utils.dart';
import 'package:stackwallet/utilities/amount/amount.dart';
import 'package:stackwallet/utilities/assets.dart';
import 'package:stackwallet/utilities/barcode_scanner_interface.dart';
import 'package:stackwallet/utilities/clipboard_interface.dart';
import 'package:stackwallet/utilities/constants.dart';
import 'package:stackwallet/utilities/enums/coin_enum.dart';
import 'package:stackwallet/utilities/enums/fee_rate_type_enum.dart';
import 'package:stackwallet/utilities/logger.dart';
import 'package:stackwallet/utilities/prefs.dart';
import 'package:stackwallet/utilities/text_styles.dart';
import 'package:stackwallet/utilities/theme/stack_colors.dart';
import 'package:stackwallet/utilities/util.dart';
import 'package:stackwallet/widgets/animated_text.dart';
import 'package:stackwallet/widgets/background.dart';
import 'package:stackwallet/widgets/custom_buttons/app_bar_icon_button.dart';
import 'package:stackwallet/widgets/icon_widgets/addressbook_icon.dart';
import 'package:stackwallet/widgets/icon_widgets/clipboard_icon.dart';
import 'package:stackwallet/widgets/icon_widgets/eth_token_icon.dart';
import 'package:stackwallet/widgets/icon_widgets/qrcode_icon.dart';
import 'package:stackwallet/widgets/icon_widgets/x_icon.dart';
import 'package:stackwallet/widgets/stack_dialog.dart';
import 'package:stackwallet/widgets/stack_text_field.dart';
import 'package:stackwallet/widgets/textfield_icon_button.dart';

class TokenSendView extends ConsumerStatefulWidget {
  const TokenSendView({
    Key? key,
    required this.walletId,
    required this.coin,
    required this.tokenContract,
    this.autoFillData,
    this.clipboard = const ClipboardWrapper(),
    this.barcodeScanner = const BarcodeScannerWrapper(),
  }) : super(key: key);

  static const String routeName = "/tokenSendView";

  final String walletId;
  final Coin coin;
  final EthContract tokenContract;
  final SendViewAutoFillData? autoFillData;
  final ClipboardInterface clipboard;
  final BarcodeScannerInterface barcodeScanner;

  @override
  ConsumerState<TokenSendView> createState() => _TokenSendViewState();
}

class _TokenSendViewState extends ConsumerState<TokenSendView> {
  late final String walletId;
  late final Coin coin;
  late final EthContract tokenContract;
  late final ClipboardInterface clipboard;
  late final BarcodeScannerInterface scanner;

  late TextEditingController sendToController;
  late TextEditingController cryptoAmountController;
  late TextEditingController baseAmountController;
  late TextEditingController noteController;
  late TextEditingController feeController;

  late final SendViewAutoFillData? _data;

  final _addressFocusNode = FocusNode();
  final _noteFocusNode = FocusNode();
  final _cryptoFocus = FocusNode();
  final _baseFocus = FocusNode();

  Amount? _amountToSend;
  Amount? _cachedAmountToSend;
  String? _address;

  bool _addressToggleFlag = false;

  bool _cryptoAmountChangeLock = false;
  late VoidCallback onCryptoAmountChanged;

  final updateFeesTimerDuration = const Duration(milliseconds: 500);

  Timer? _cryptoAmountChangedFeeUpdateTimer;
  Timer? _baseAmountChangedFeeUpdateTimer;
  late Future<String> _calculateFeesFuture;
  String cachedFees = "";

  void _onTokenSendViewPasteAddressFieldButtonPressed() async {
    final ClipboardData? data = await clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      String content = data.text!.trim();
      if (content.contains("\n")) {
        content = content.substring(0, content.indexOf("\n"));
      }
      sendToController.text = content.trim();
      _address = content.trim();

      _updatePreviewButtonState(_address, _amountToSend);
      setState(() {
        _addressToggleFlag = sendToController.text.isNotEmpty;
      });
    }
  }

  void _onTokenSendViewScanQrButtonPressed() async {
    try {
      // ref
      //     .read(
      //         shouldShowLockscreenOnResumeStateProvider
      //             .state)
      //     .state = false;
      if (FocusScope.of(context).hasFocus) {
        FocusScope.of(context).unfocus();
        await Future<void>.delayed(const Duration(milliseconds: 75));
      }

      final qrResult = await scanner.scan();

      // Future<void>.delayed(
      //   const Duration(seconds: 2),
      //   () => ref
      //       .read(
      //           shouldShowLockscreenOnResumeStateProvider
      //               .state)
      //       .state = true,
      // );

      Logging.instance.log("qrResult content: ${qrResult.rawContent}",
          level: LogLevel.Info);

      final results = AddressUtils.parseUri(qrResult.rawContent);

      Logging.instance.log("qrResult parsed: $results", level: LogLevel.Info);

      if (results.isNotEmpty && results["scheme"] == coin.uriScheme) {
        // auto fill address
        _address = (results["address"] ?? "").trim();
        sendToController.text = _address!;

        // autofill notes field
        if (results["message"] != null) {
          noteController.text = results["message"]!;
        } else if (results["label"] != null) {
          noteController.text = results["label"]!;
        }

        // autofill amount field
        if (results["amount"] != null) {
          final Amount amount = Decimal.parse(results["amount"]!).toAmount(
            fractionDigits: tokenContract.decimals,
          );
          cryptoAmountController.text = amount.localizedStringAsFixed(
            locale: ref.read(localeServiceChangeNotifierProvider).locale,
          );
          _amountToSend = amount;
        }

        _updatePreviewButtonState(_address, _amountToSend);
        setState(() {
          _addressToggleFlag = sendToController.text.isNotEmpty;
        });

        // now check for non standard encoded basic address
      } else if (ref
          .read(walletsChangeNotifierProvider)
          .getManager(walletId)
          .validateAddress(qrResult.rawContent)) {
        _address = qrResult.rawContent.trim();
        sendToController.text = _address ?? "";

        _updatePreviewButtonState(_address, _amountToSend);
        setState(() {
          _addressToggleFlag = sendToController.text.isNotEmpty;
        });
      }
    } on PlatformException catch (e, s) {
      // ref
      //     .read(
      //         shouldShowLockscreenOnResumeStateProvider
      //             .state)
      //     .state = true;
      // here we ignore the exception caused by not giving permission
      // to use the camera to scan a qr code
      Logging.instance.log(
          "Failed to get camera permissions while trying to scan qr code in SendView: $e\n$s",
          level: LogLevel.Warning);
    }
  }

  void _onFiatAmountFieldChanged(String baseAmountString) {
    if (baseAmountString.isNotEmpty &&
        baseAmountString != "." &&
        baseAmountString != ",") {
      final baseAmount = Amount.fromDecimal(
        baseAmountString.contains(",")
            ? Decimal.parse(baseAmountString.replaceFirst(",", "."))
            : Decimal.parse(baseAmountString),
        fractionDigits: tokenContract.decimals,
      );

      final _price = ref
          .read(priceAnd24hChangeNotifierProvider)
          .getTokenPrice(tokenContract.address)
          .item1;

      if (_price == Decimal.zero) {
        _amountToSend = Amount.zero;
      } else {
        _amountToSend = baseAmount <= Amount.zero
            ? Amount.zero
            : Amount.fromDecimal(
                (baseAmount.decimal / _price).toDecimal(
                    scaleOnInfinitePrecision: tokenContract.decimals),
                fractionDigits: tokenContract.decimals);
      }
      if (_cachedAmountToSend != null && _cachedAmountToSend == _amountToSend) {
        return;
      }
      _cachedAmountToSend = _amountToSend;
      Logging.instance.log("it changed $_amountToSend $_cachedAmountToSend",
          level: LogLevel.Info);

      _cryptoAmountChangeLock = true;
      cryptoAmountController.text = _amountToSend!.localizedStringAsFixed(
        locale: ref.read(localeServiceChangeNotifierProvider).locale,
      );
      _cryptoAmountChangeLock = false;
    } else {
      _amountToSend = Amount.zero;
      _cryptoAmountChangeLock = true;
      cryptoAmountController.text = "";
      _cryptoAmountChangeLock = false;
    }
    // setState(() {
    //   _calculateFeesFuture = calculateFees(
    //       Format.decimalAmountToSatoshis(
    //           _amountToSend!));
    // });
    _updatePreviewButtonState(_address, _amountToSend);
  }

  void _cryptoAmountChanged() async {
    if (!_cryptoAmountChangeLock) {
      final String cryptoAmount = cryptoAmountController.text;
      if (cryptoAmount.isNotEmpty &&
          cryptoAmount != "." &&
          cryptoAmount != ",") {
        _amountToSend = Amount.fromDecimal(
            cryptoAmount.contains(",")
                ? Decimal.parse(cryptoAmount.replaceFirst(",", "."))
                : Decimal.parse(cryptoAmount),
            fractionDigits: tokenContract.decimals);
        if (_cachedAmountToSend != null &&
            _cachedAmountToSend == _amountToSend) {
          return;
        }
        _cachedAmountToSend = _amountToSend;
        Logging.instance.log("it changed $_amountToSend $_cachedAmountToSend",
            level: LogLevel.Info);

        final price = ref
            .read(priceAnd24hChangeNotifierProvider)
            .getTokenPrice(tokenContract.address)
            .item1;

        if (price > Decimal.zero) {
          baseAmountController.text = (_amountToSend!.decimal * price)
              .toAmount(
                fractionDigits: 2,
              )
              .localizedStringAsFixed(
                locale: ref.read(localeServiceChangeNotifierProvider).locale,
              );
        }
      } else {
        _amountToSend = null;
        baseAmountController.text = "";
      }

      _updatePreviewButtonState(_address, _amountToSend);

      _cryptoAmountChangedFeeUpdateTimer?.cancel();
      _cryptoAmountChangedFeeUpdateTimer = Timer(updateFeesTimerDuration, () {
        if (coin != Coin.epicCash && !_baseFocus.hasFocus) {
          setState(() {
            _calculateFeesFuture = calculateFees();
          });
        }
      });
    }
  }

  void _baseAmountChanged() {
    _baseAmountChangedFeeUpdateTimer?.cancel();
    _baseAmountChangedFeeUpdateTimer = Timer(updateFeesTimerDuration, () {
      if (coin != Coin.epicCash && !_cryptoFocus.hasFocus) {
        setState(() {
          _calculateFeesFuture = calculateFees();
        });
      }
    });
  }

  String? _updateInvalidAddressText(String address, Manager manager) {
    if (_data != null && _data!.contactLabel == address) {
      return null;
    }
    if (address.isNotEmpty && !manager.validateAddress(address)) {
      return "Invalid address";
    }
    return null;
  }

  void _updatePreviewButtonState(String? address, Amount? amount) {
    final isValidAddress = ref
        .read(walletsChangeNotifierProvider)
        .getManager(walletId)
        .validateAddress(address ?? "");
    ref.read(previewTxButtonStateProvider.state).state =
        (isValidAddress && amount != null && amount > Amount.zero);
  }

  Future<String> calculateFees() async {
    final wallet = ref.read(tokenServiceProvider)!;
    final feeObject = await wallet.fees;

    late final int feeRate;

    switch (ref.read(feeRateTypeStateProvider.state).state) {
      case FeeRateType.fast:
        feeRate = feeObject.fast;
        break;
      case FeeRateType.average:
        feeRate = feeObject.medium;
        break;
      case FeeRateType.slow:
        feeRate = feeObject.slow;
        break;
    }

    final Amount fee = wallet.estimateFeeFor(feeRate);
    cachedFees = fee.localizedStringAsFixed(
      locale: ref.read(localeServiceChangeNotifierProvider).locale,
    );

    return cachedFees;
  }

  Future<void> _previewTransaction() async {
    // wait for keyboard to disappear
    FocusScope.of(context).unfocus();
    await Future<void>.delayed(
      const Duration(milliseconds: 100),
    );
    final manager =
        ref.read(walletsChangeNotifierProvider).getManager(walletId);
    final tokenWallet = ref.read(tokenServiceProvider)!;

    final Amount amount = _amountToSend!;

    // // confirm send all
    // if (amount == availableBalance) {
    //   bool? shouldSendAll;
    //   if (mounted) {
    //     shouldSendAll = await showDialog<bool>(
    //       context: context,
    //       useSafeArea: false,
    //       barrierDismissible: true,
    //       builder: (context) {
    //         return StackDialog(
    //           title: "Confirm send all",
    //           message:
    //               "You are about to send your entire balance. Would you like to continue?",
    //           leftButton: TextButton(
    //             style: Theme.of(context)
    //                 .extension<StackColors>()!
    //                 .getSecondaryEnabledButtonStyle(context),
    //             child: Text(
    //               "Cancel",
    //               style: STextStyles.button(context).copyWith(
    //                   color: Theme.of(context)
    //                       .extension<StackColors>()!
    //                       .accentColorDark),
    //             ),
    //             onPressed: () {
    //               Navigator.of(context).pop(false);
    //             },
    //           ),
    //           rightButton: TextButton(
    //             style: Theme.of(context)
    //                 .extension<StackColors>()!
    //                 .getPrimaryEnabledButtonStyle(context),
    //             child: Text(
    //               "Yes",
    //               style: STextStyles.button(context),
    //             ),
    //             onPressed: () {
    //               Navigator.of(context).pop(true);
    //             },
    //           ),
    //         );
    //       },
    //     );
    //   }
    //
    //   if (shouldSendAll == null || shouldSendAll == false) {
    //     // cancel preview
    //     return;
    //   }
    // }

    try {
      bool wasCancelled = false;

      if (mounted) {
        unawaited(
          showDialog<void>(
            context: context,
            useSafeArea: false,
            barrierDismissible: false,
            builder: (context) {
              return BuildingTransactionDialog(
                coin: manager.coin,
                onCancel: () {
                  wasCancelled = true;

                  Navigator.of(context).pop();
                },
              );
            },
          ),
        );
      }

      final time = Future<dynamic>.delayed(
        const Duration(
          milliseconds: 2500,
        ),
      );

      Map<String, dynamic> txData;
      Future<Map<String, dynamic>> txDataFuture;

      txDataFuture = tokenWallet.prepareSend(
        address: _address!,
        amount: amount,
        args: {
          "feeRate": ref.read(feeRateTypeStateProvider),
        },
      );

      final results = await Future.wait([
        txDataFuture,
        time,
      ]);

      txData = results.first as Map<String, dynamic>;

      if (!wasCancelled && mounted) {
        // pop building dialog
        Navigator.of(context).pop();
        txData["note"] = noteController.text;

        txData["address"] = _address;

        unawaited(Navigator.of(context).push(
          RouteGenerator.getRoute(
            shouldUseMaterialRoute: RouteGenerator.useMaterialPageRoute,
            builder: (_) => ConfirmTransactionView(
              transactionInfo: txData,
              walletId: walletId,
              isTokenTx: true,
            ),
            settings: const RouteSettings(
              name: ConfirmTransactionView.routeName,
            ),
          ),
        ));
      }
    } catch (e) {
      if (mounted) {
        // pop building dialog
        Navigator.of(context).pop();

        unawaited(showDialog<dynamic>(
          context: context,
          useSafeArea: false,
          barrierDismissible: true,
          builder: (context) {
            return StackDialog(
              title: "Transaction failed",
              message: e.toString(),
              rightButton: TextButton(
                style: Theme.of(context)
                    .extension<StackColors>()!
                    .getSecondaryEnabledButtonStyle(context),
                child: Text(
                  "Ok",
                  style: STextStyles.button(context).copyWith(
                      color: Theme.of(context)
                          .extension<StackColors>()!
                          .accentColorDark),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            );
          },
        ));
      }
    }
  }

  @override
  void initState() {
    ref.refresh(feeSheetSessionCacheProvider);

    _calculateFeesFuture = calculateFees();
    _data = widget.autoFillData;
    walletId = widget.walletId;
    coin = widget.coin;
    tokenContract = widget.tokenContract;
    clipboard = widget.clipboard;
    scanner = widget.barcodeScanner;

    sendToController = TextEditingController();
    cryptoAmountController = TextEditingController();
    baseAmountController = TextEditingController();
    noteController = TextEditingController();
    feeController = TextEditingController();

    onCryptoAmountChanged = _cryptoAmountChanged;
    cryptoAmountController.addListener(onCryptoAmountChanged);
    baseAmountController.addListener(_baseAmountChanged);

    if (_data != null) {
      if (_data!.amount != null) {
        cryptoAmountController.text = _data!.amount!.toString();
      }
      sendToController.text = _data!.contactLabel;
      _address = _data!.address.trim();
      _addressToggleFlag = true;
    }

    super.initState();
  }

  @override
  void dispose() {
    _cryptoAmountChangedFeeUpdateTimer?.cancel();
    _baseAmountChangedFeeUpdateTimer?.cancel();

    cryptoAmountController.removeListener(onCryptoAmountChanged);
    baseAmountController.removeListener(_baseAmountChanged);

    sendToController.dispose();
    cryptoAmountController.dispose();
    baseAmountController.dispose();
    noteController.dispose();
    feeController.dispose();

    _noteFocusNode.dispose();
    _addressFocusNode.dispose();
    _cryptoFocus.dispose();
    _baseFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("BUILD: $runtimeType");
    final provider = ref.watch(walletsChangeNotifierProvider
        .select((value) => value.getManagerProvider(walletId)));
    final String locale = ref.watch(
        localeServiceChangeNotifierProvider.select((value) => value.locale));

    return Background(
      child: Scaffold(
        backgroundColor: Theme.of(context).extension<StackColors>()!.background,
        appBar: AppBar(
          leading: AppBarBackButton(
            onPressed: () async {
              if (FocusScope.of(context).hasFocus) {
                FocusScope.of(context).unfocus();
                await Future<void>.delayed(const Duration(milliseconds: 50));
              }
              if (mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          title: Text(
            "Send ${tokenContract.symbol}",
            style: STextStyles.navBarTitle(context),
          ),
        ),
        body: LayoutBuilder(
          builder: (builderContext, constraints) {
            return Padding(
              padding: const EdgeInsets.only(
                left: 12,
                top: 12,
                right: 12,
              ),
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    // subtract top and bottom padding set in parent
                    minHeight: constraints.maxHeight - 24,
                  ),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .extension<StackColors>()!
                                  .popupBG,
                              borderRadius: BorderRadius.circular(
                                Constants.size.circularBorderRadius,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                children: [
                                  EthTokenIcon(
                                    contractAddress: tokenContract.address,
                                  ),
                                  const SizedBox(
                                    width: 6,
                                  ),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        ref.watch(provider.select(
                                            (value) => value.walletName)),
                                        style: STextStyles.titleBold12(context)
                                            .copyWith(fontSize: 14),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                      Text(
                                        "Available balance",
                                        style: STextStyles.label(context)
                                            .copyWith(fontSize: 10),
                                      ),
                                    ],
                                  ),
                                  const Spacer(),
                                  GestureDetector(
                                    onTap: () {
                                      cryptoAmountController.text = ref
                                          .read(tokenServiceProvider)!
                                          .balance
                                          .spendable
                                          .localizedStringAsFixed(
                                            locale: ref
                                                .read(
                                                    localeServiceChangeNotifierProvider)
                                                .locale,
                                          );
                                    },
                                    child: Container(
                                      color: Colors.transparent,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            "${ref.watch(
                                              tokenServiceProvider.select(
                                                (value) => value!
                                                    .balance.spendable
                                                    .localizedStringAsFixed(
                                                  locale: ref.watch(
                                                    localeServiceChangeNotifierProvider
                                                        .select(
                                                      (value) => value.locale,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            )} ${tokenContract.symbol}",
                                            style:
                                                STextStyles.titleBold12(context)
                                                    .copyWith(
                                              fontSize: 10,
                                            ),
                                            textAlign: TextAlign.right,
                                          ),
                                          Text(
                                            "${(ref.watch(tokenServiceProvider.select((value) => value!.balance.spendable.decimal)) * ref.watch(priceAnd24hChangeNotifierProvider.select((value) => value.getTokenPrice(tokenContract.address).item1))).toAmount(
                                                  fractionDigits: 2,
                                                ).localizedStringAsFixed(
                                                  locale: locale,
                                                )} ${ref.watch(prefsChangeNotifierProvider.select((value) => value.currency))}",
                                            style: STextStyles.subtitle(context)
                                                .copyWith(
                                              fontSize: 8,
                                            ),
                                            textAlign: TextAlign.right,
                                          )
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(
                            height: 16,
                          ),
                          Text(
                            "Send to",
                            style: STextStyles.smallMed12(context),
                            textAlign: TextAlign.left,
                          ),
                          const SizedBox(
                            height: 8,
                          ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              Constants.size.circularBorderRadius,
                            ),
                            child: TextField(
                              key: const Key("tokenSendViewAddressFieldKey"),
                              controller: sendToController,
                              readOnly: false,
                              autocorrect: false,
                              enableSuggestions: false,
                              toolbarOptions: const ToolbarOptions(
                                copy: false,
                                cut: false,
                                paste: true,
                                selectAll: false,
                              ),
                              onChanged: (newValue) {
                                _address = newValue.trim();
                                _updatePreviewButtonState(
                                    _address, _amountToSend);

                                setState(() {
                                  _addressToggleFlag = newValue.isNotEmpty;
                                });
                              },
                              focusNode: _addressFocusNode,
                              style: STextStyles.field(context),
                              decoration: standardInputDecoration(
                                "Enter ${tokenContract.symbol} address",
                                _addressFocusNode,
                                context,
                              ).copyWith(
                                contentPadding: const EdgeInsets.only(
                                  left: 16,
                                  top: 6,
                                  bottom: 8,
                                  right: 5,
                                ),
                                suffixIcon: Padding(
                                  padding: sendToController.text.isEmpty
                                      ? const EdgeInsets.only(right: 8)
                                      : const EdgeInsets.only(right: 0),
                                  child: UnconstrainedBox(
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceAround,
                                      children: [
                                        _addressToggleFlag
                                            ? TextFieldIconButton(
                                                key: const Key(
                                                    "tokenSendViewClearAddressFieldButtonKey"),
                                                onTap: () {
                                                  sendToController.text = "";
                                                  _address = "";
                                                  _updatePreviewButtonState(
                                                      _address, _amountToSend);
                                                  setState(() {
                                                    _addressToggleFlag = false;
                                                  });
                                                },
                                                child: const XIcon(),
                                              )
                                            : TextFieldIconButton(
                                                key: const Key(
                                                    "tokenSendViewPasteAddressFieldButtonKey"),
                                                onTap:
                                                    _onTokenSendViewPasteAddressFieldButtonPressed,
                                                child: sendToController
                                                        .text.isEmpty
                                                    ? const ClipboardIcon()
                                                    : const XIcon(),
                                              ),
                                        if (sendToController.text.isEmpty)
                                          TextFieldIconButton(
                                            key: const Key(
                                                "sendViewAddressBookButtonKey"),
                                            onTap: () {
                                              Navigator.of(context).pushNamed(
                                                AddressBookView.routeName,
                                                arguments: widget.coin,
                                              );
                                            },
                                            child: const AddressBookIcon(),
                                          ),
                                        if (sendToController.text.isEmpty)
                                          TextFieldIconButton(
                                            key: const Key(
                                                "sendViewScanQrButtonKey"),
                                            onTap:
                                                _onTokenSendViewScanQrButtonPressed,
                                            child: const QrCodeIcon(),
                                          )
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Builder(
                            builder: (_) {
                              final error = _updateInvalidAddressText(
                                _address ?? "",
                                ref
                                    .read(walletsChangeNotifierProvider)
                                    .getManager(walletId),
                              );

                              if (error == null || error.isEmpty) {
                                return Container();
                              } else {
                                return Align(
                                  alignment: Alignment.topLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      left: 12.0,
                                      top: 4.0,
                                    ),
                                    child: Text(
                                      error,
                                      textAlign: TextAlign.left,
                                      style:
                                          STextStyles.label(context).copyWith(
                                        color: Theme.of(context)
                                            .extension<StackColors>()!
                                            .textError,
                                      ),
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                          const SizedBox(
                            height: 12,
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Amount",
                                style: STextStyles.smallMed12(context),
                                textAlign: TextAlign.left,
                              ),
                              // CustomTextButton(
                              //   text: "Send all ${tokenContract.symbol}",
                              //   onTap: () async {
                              //     cryptoAmountController.text = ref
                              //         .read(tokenServiceProvider)!
                              //         .balance
                              //         .getSpendable()
                              //         .toStringAsFixed(tokenContract.decimals);
                              //
                              //     _cryptoAmountChanged();
                              //   },
                              // ),
                            ],
                          ),
                          const SizedBox(
                            height: 8,
                          ),
                          TextField(
                            autocorrect: Util.isDesktop ? false : true,
                            enableSuggestions: Util.isDesktop ? false : true,
                            style: STextStyles.smallMed14(context).copyWith(
                              color: Theme.of(context)
                                  .extension<StackColors>()!
                                  .textDark,
                            ),
                            key:
                                const Key("amountInputFieldCryptoTextFieldKey"),
                            controller: cryptoAmountController,
                            focusNode: _cryptoFocus,
                            keyboardType: Util.isDesktop
                                ? null
                                : const TextInputType.numberWithOptions(
                                    signed: false,
                                    decimal: true,
                                  ),
                            textAlign: TextAlign.right,
                            inputFormatters: [
                              // regex to validate a crypto amount with 8 decimal places
                              TextInputFormatter.withFunction((oldValue,
                                      newValue) =>
                                  RegExp(r'^([0-9]*[,.]?[0-9]{0,8}|[,.][0-9]{0,8})$')
                                          .hasMatch(newValue.text)
                                      ? newValue
                                      : oldValue),
                            ],
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.only(
                                top: 12,
                                right: 12,
                              ),
                              hintText: "0",
                              hintStyle:
                                  STextStyles.fieldLabel(context).copyWith(
                                fontSize: 14,
                              ),
                              prefixIcon: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    tokenContract.symbol,
                                    style: STextStyles.smallMed14(context)
                                        .copyWith(
                                            color: Theme.of(context)
                                                .extension<StackColors>()!
                                                .accentColorDark),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (Prefs.instance.externalCalls)
                            const SizedBox(
                              height: 8,
                            ),
                          if (Prefs.instance.externalCalls)
                            TextField(
                              autocorrect: Util.isDesktop ? false : true,
                              enableSuggestions: Util.isDesktop ? false : true,
                              style: STextStyles.smallMed14(context).copyWith(
                                color: Theme.of(context)
                                    .extension<StackColors>()!
                                    .textDark,
                              ),
                              key:
                                  const Key("amountInputFieldFiatTextFieldKey"),
                              controller: baseAmountController,
                              focusNode: _baseFocus,
                              keyboardType: Util.isDesktop
                                  ? null
                                  : const TextInputType.numberWithOptions(
                                      signed: false,
                                      decimal: true,
                                    ),
                              textAlign: TextAlign.right,
                              inputFormatters: [
                                // regex to validate a fiat amount with 2 decimal places
                                TextInputFormatter.withFunction((oldValue,
                                        newValue) =>
                                    RegExp(r'^([0-9]*[,.]?[0-9]{0,2}|[,.][0-9]{0,2})$')
                                            .hasMatch(newValue.text)
                                        ? newValue
                                        : oldValue),
                              ],
                              onChanged: _onFiatAmountFieldChanged,
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.only(
                                  top: 12,
                                  right: 12,
                                ),
                                hintText: "0",
                                hintStyle:
                                    STextStyles.fieldLabel(context).copyWith(
                                  fontSize: 14,
                                ),
                                prefixIcon: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      ref.watch(prefsChangeNotifierProvider
                                          .select((value) => value.currency)),
                                      style: STextStyles.smallMed14(context)
                                          .copyWith(
                                              color: Theme.of(context)
                                                  .extension<StackColors>()!
                                                  .accentColorDark),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(
                            height: 12,
                          ),
                          Text(
                            "Note (optional)",
                            style: STextStyles.smallMed12(context),
                            textAlign: TextAlign.left,
                          ),
                          const SizedBox(
                            height: 8,
                          ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              Constants.size.circularBorderRadius,
                            ),
                            child: TextField(
                              autocorrect: Util.isDesktop ? false : true,
                              enableSuggestions: Util.isDesktop ? false : true,
                              controller: noteController,
                              focusNode: _noteFocusNode,
                              style: STextStyles.field(context),
                              onChanged: (_) => setState(() {}),
                              decoration: standardInputDecoration(
                                "Type something...",
                                _noteFocusNode,
                                context,
                              ).copyWith(
                                suffixIcon: noteController.text.isNotEmpty
                                    ? Padding(
                                        padding:
                                            const EdgeInsets.only(right: 0),
                                        child: UnconstrainedBox(
                                          child: Row(
                                            children: [
                                              TextFieldIconButton(
                                                child: const XIcon(),
                                                onTap: () async {
                                                  setState(() {
                                                    noteController.text = "";
                                                  });
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(
                            height: 12,
                          ),
                          if (coin != Coin.epicCash)
                            Text(
                              "Transaction fee (estimated)",
                              style: STextStyles.smallMed12(context),
                              textAlign: TextAlign.left,
                            ),
                          const SizedBox(
                            height: 8,
                          ),
                          Stack(
                            children: [
                              TextField(
                                autocorrect: Util.isDesktop ? false : true,
                                enableSuggestions:
                                    Util.isDesktop ? false : true,
                                controller: feeController,
                                readOnly: true,
                                textInputAction: TextInputAction.none,
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: RawMaterialButton(
                                  splashColor: Theme.of(context)
                                      .extension<StackColors>()!
                                      .highlight,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      Constants.size.circularBorderRadius,
                                    ),
                                  ),
                                  onPressed: () {
                                    showModalBottomSheet<dynamic>(
                                      backgroundColor: Colors.transparent,
                                      context: context,
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(20),
                                        ),
                                      ),
                                      builder: (_) =>
                                          TransactionFeeSelectionSheet(
                                        walletId: walletId,
                                        isToken: true,
                                        amount: (Decimal.tryParse(
                                                    cryptoAmountController
                                                        .text) ??
                                                Decimal.zero)
                                            .toAmount(
                                          fractionDigits:
                                              tokenContract.decimals,
                                        ),
                                        updateChosen: (String fee) {
                                          setState(() {
                                            _calculateFeesFuture =
                                                Future(() => fee);
                                          });
                                        },
                                      ),
                                    );
                                  },
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            ref
                                                .watch(feeRateTypeStateProvider
                                                    .state)
                                                .state
                                                .prettyName,
                                            style: STextStyles.itemSubtitle12(
                                                context),
                                          ),
                                          const SizedBox(
                                            width: 10,
                                          ),
                                          FutureBuilder(
                                            future: _calculateFeesFuture,
                                            builder: (context, snapshot) {
                                              if (snapshot.connectionState ==
                                                      ConnectionState.done &&
                                                  snapshot.hasData) {
                                                return Text(
                                                  "~${snapshot.data! as String} ${coin.ticker}",
                                                  style:
                                                      STextStyles.itemSubtitle(
                                                          context),
                                                );
                                              } else {
                                                return AnimatedText(
                                                  stringsToLoopThrough: const [
                                                    "Calculating",
                                                    "Calculating.",
                                                    "Calculating..",
                                                    "Calculating...",
                                                  ],
                                                  style:
                                                      STextStyles.itemSubtitle(
                                                          context),
                                                );
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                      SvgPicture.asset(
                                        Assets.svg.chevronDown,
                                        width: 8,
                                        height: 4,
                                        color: Theme.of(context)
                                            .extension<StackColors>()!
                                            .textSubtitle2,
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            ],
                          ),
                          const Spacer(),
                          const SizedBox(
                            height: 12,
                          ),
                          TextButton(
                            onPressed: ref
                                    .watch(previewTxButtonStateProvider.state)
                                    .state
                                ? _previewTransaction
                                : null,
                            style: ref
                                    .watch(previewTxButtonStateProvider.state)
                                    .state
                                ? Theme.of(context)
                                    .extension<StackColors>()!
                                    .getPrimaryEnabledButtonStyle(context)
                                : Theme.of(context)
                                    .extension<StackColors>()!
                                    .getPrimaryDisabledButtonStyle(context),
                            child: Text(
                              "Preview",
                              style: STextStyles.button(context),
                            ),
                          ),
                          const SizedBox(
                            height: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}