import 'dart:async';
import 'dart:math';

import 'package:cw_core/monero_transaction_priority.dart';
import 'package:cw_core/node.dart';
import 'package:cw_core/pending_transaction.dart';
import 'package:cw_core/sync_status.dart';
import 'package:cw_core/transaction_direction.dart';
import 'package:cw_core/wallet_base.dart';
import 'package:cw_core/wallet_credentials.dart';
import 'package:cw_core/wallet_info.dart';
import 'package:cw_core/wallet_type.dart';
import 'package:cw_monero/api/exceptions/creation_transaction_exception.dart';
import 'package:cw_wownero/api/wallet.dart';
import 'package:cw_wownero/pending_wownero_transaction.dart';
import 'package:cw_wownero/wownero_wallet.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_libmonero/core/wallet_creation_service.dart';
import 'package:flutter_libmonero/view_model/send/output.dart'
    as wownero_output;
import 'package:flutter_libmonero/wownero/wownero.dart' as wow_dart;
import 'package:isar/isar.dart';
import 'package:stackwallet/db/hive/db.dart';
import 'package:stackwallet/models/isar/models/blockchain_data/address.dart';
import 'package:stackwallet/models/isar/models/blockchain_data/transaction.dart';
import 'package:stackwallet/utilities/amount/amount.dart';
import 'package:stackwallet/utilities/enums/fee_rate_type_enum.dart';
import 'package:stackwallet/utilities/logger.dart';
import 'package:stackwallet/wallets/crypto_currency/coins/wownero.dart';
import 'package:stackwallet/wallets/crypto_currency/crypto_currency.dart';
import 'package:stackwallet/wallets/models/tx_data.dart';
import 'package:stackwallet/wallets/wallet/intermediate/cryptonote_wallet.dart';
import 'package:stackwallet/wallets/wallet/wallet.dart';
import 'package:stackwallet/wallets/wallet/wallet_mixin_interfaces/cw_based_interface.dart';
import 'package:tuple/tuple.dart';

class WowneroWallet extends CryptonoteWallet with CwBasedInterface {
  WowneroWallet(CryptoCurrencyNetwork network) : super(Wownero(network));

  @override
  Address addressFor({required int index, int account = 0}) {
    String address = (CwBasedInterface.cwWalletBase as WowneroWalletBase)
        .getTransactionAddress(account, index);

    final newReceivingAddress = Address(
      walletId: walletId,
      derivationIndex: index,
      derivationPath: null,
      value: address,
      publicKey: [],
      type: AddressType.cryptonote,
      subType: AddressSubType.receiving,
    );

    return newReceivingAddress;
  }

  @override
  Future<Amount> estimateFeeFor(Amount amount, int feeRate) async {
    if (CwBasedInterface.cwWalletBase == null ||
        CwBasedInterface.cwWalletBase?.syncStatus is! SyncedSyncStatus) {
      return Amount.zeroWith(
        fractionDigits: cryptoCurrency.fractionDigits,
      );
    }

    MoneroTransactionPriority priority;
    FeeRateType feeRateType = FeeRateType.slow;
    switch (feeRate) {
      case 1:
        priority = MoneroTransactionPriority.regular;
        feeRateType = FeeRateType.average;
        break;
      case 2:
        priority = MoneroTransactionPriority.medium;
        feeRateType = FeeRateType.average;
        break;
      case 3:
        priority = MoneroTransactionPriority.fast;
        feeRateType = FeeRateType.fast;
        break;
      case 4:
        priority = MoneroTransactionPriority.fastest;
        feeRateType = FeeRateType.fast;
        break;
      case 0:
      default:
        priority = MoneroTransactionPriority.slow;
        feeRateType = FeeRateType.slow;
        break;
    }

    dynamic approximateFee;
    await estimateFeeMutex.protect(() async {
      {
        try {
          final data = await prepareSend(
            txData: TxData(
              recipients: [
                // This address is only used for getting an approximate fee, never for sending
                (
                  address:
                      "WW3iVcnoAY6K9zNdU4qmdvZELefx6xZz4PMpTwUifRkvMQckyadhSPYMVPJhBdYE8P9c27fg9RPmVaWNFx1cDaj61HnetqBiy",
                  amount: amount,
                  isChange: false,
                ),
              ],
              feeRateType: feeRateType,
            ),
          );
          approximateFee = data.fee!;

          // unsure why this delay?
          await Future<void>.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          approximateFee = CwBasedInterface.cwWalletBase!.calculateEstimatedFee(
            priority,
            amount.raw.toInt(),
          );
        }
      }
    });

    if (approximateFee is Amount) {
      return approximateFee as Amount;
    } else {
      return Amount(
        rawValue: BigInt.from(approximateFee as int),
        fractionDigits: cryptoCurrency.fractionDigits,
      );
    }
  }

  @override
  Future<bool> pingCheck() async {
    return await (CwBasedInterface.cwWalletBase as WowneroWalletBase?)
            ?.isConnected() ??
        false;
  }

  @override
  Future<void> updateNode() async {
    final node = getCurrentNode();

    final host = Uri.parse(node.host).host;
    await CwBasedInterface.cwWalletBase?.connectToNode(
      node: Node(
        uri: "$host:${node.port}",
        type: WalletType.wownero,
        trusted: node.trusted ?? false,
      ),
    );
  }

  @override
  Future<void> updateTransactions() async {
    final base = (CwBasedInterface.cwWalletBase as WowneroWalletBase?);

    if (base == null ||
        base.walletInfo.name != walletId ||
        CwBasedInterface.exitMutex.isLocked) {
      return;
    }
    await base.updateTransactions();
    final transactions = base.transactionHistory?.transactions;

    // final cachedTransactions =
    // DB.instance.get<dynamic>(boxName: walletId, key: 'latest_tx_model')
    // as TransactionData?;
    // int latestTxnBlockHeight =
    //     DB.instance.get<dynamic>(boxName: walletId, key: "storedTxnDataHeight")
    //     as int? ??
    //         0;
    //
    // final txidsList = DB.instance
    //     .get<dynamic>(boxName: walletId, key: "cachedTxids") as List? ??
    //     [];
    //
    // final Set<String> cachedTxids = Set<String>.from(txidsList);

    // TODO: filter to skip cached + confirmed txn processing in next step
    // final unconfirmedCachedTransactions =
    //     cachedTransactions?.getAllTransactions() ?? {};
    // unconfirmedCachedTransactions
    //     .removeWhere((key, value) => value.confirmedStatus);
    //
    // if (cachedTransactions != null) {
    //   for (final tx in allTxHashes.toList(growable: false)) {
    //     final txHeight = tx["height"] as int;
    //     if (txHeight > 0 &&
    //         txHeight < latestTxnBlockHeight - MINIMUM_CONFIRMATIONS) {
    //       if (unconfirmedCachedTransactions[tx["tx_hash"] as String] == null) {
    //         allTxHashes.remove(tx);
    //       }
    //     }
    //   }
    // }

    final List<Tuple2<Transaction, Address?>> txnsData = [];

    if (transactions != null) {
      for (var tx in transactions.entries) {
        Address? address;
        TransactionType type;
        if (tx.value.direction == TransactionDirection.incoming) {
          final addressInfo = tx.value.additionalInfo;

          final addressString =
              (CwBasedInterface.cwWalletBase as WowneroWalletBase?)
                  ?.getTransactionAddress(
            addressInfo!['accountIndex'] as int,
            addressInfo['addressIndex'] as int,
          );

          if (addressString != null) {
            address = await mainDB
                .getAddresses(walletId)
                .filter()
                .valueEqualTo(addressString)
                .findFirst();
          }

          type = TransactionType.incoming;
        } else {
          // txn.address = "";
          type = TransactionType.outgoing;
        }

        final txn = Transaction(
          walletId: walletId,
          txid: tx.value.id,
          timestamp: (tx.value.date.millisecondsSinceEpoch ~/ 1000),
          type: type,
          subType: TransactionSubType.none,
          amount: tx.value.amount ?? 0,
          amountString: Amount(
            rawValue: BigInt.from(tx.value.amount ?? 0),
            fractionDigits: cryptoCurrency.fractionDigits,
          ).toJsonString(),
          fee: tx.value.fee ?? 0,
          height: tx.value.height,
          isCancelled: false,
          isLelantus: false,
          slateId: null,
          otherData: null,
          nonce: null,
          inputs: [],
          outputs: [],
          numberOfMessages: null,
        );

        txnsData.add(Tuple2(txn, address));
      }
    }

    await mainDB.isar.writeTxn(() async {
      await mainDB.isar.transactions
          .where()
          .walletIdEqualTo(walletId)
          .deleteAll();
      for (final data in txnsData) {
        final tx = data.item1;

        // save transaction
        await mainDB.isar.transactions.put(tx);

        if (data.item2 != null) {
          final address = await mainDB.getAddress(walletId, data.item2!.value);

          // check if address exists in db and add if it does not
          if (address == null) {
            await mainDB.isar.addresses.put(data.item2!);
          }

          // link and save address
          tx.address.value = address ?? data.item2!;
          await tx.address.save();
        }
      }
    });
  }

  @override
  Future<void> init({bool? isRestore}) async {
    await CwBasedInterface.exitMutex.protect(() async {});
    CwBasedInterface.cwWalletService = wow_dart.wownero
        .createWowneroWalletService(DB.instance.moneroWalletInfoBox);

    if (!(await CwBasedInterface.cwWalletService!.isWalletExit(walletId)) &&
        isRestore != true) {
      WalletInfo walletInfo;
      WalletCredentials credentials;
      try {
        final dirPath =
            await pathForWalletDir(name: walletId, type: WalletType.wownero);
        final path =
            await pathForWallet(name: walletId, type: WalletType.wownero);
        credentials = wow_dart.wownero.createWowneroNewWalletCredentials(
          name: walletId,
          language: "English",
          seedWordsLength: 14,
        );

        walletInfo = WalletInfo.external(
          id: WalletBase.idFor(walletId, WalletType.wownero),
          name: walletId,
          type: WalletType.wownero,
          isRecovery: false,
          restoreHeight: credentials.height ?? 0,
          date: DateTime.now(),
          path: path,
          dirPath: dirPath,
          address: '',
        );
        credentials.walletInfo = walletInfo;

        final _walletCreationService = WalletCreationService(
          secureStorage: secureStorageInterface,
          walletService: CwBasedInterface.cwWalletService,
          keyService: cwKeysStorage,
        );
        // _walletCreationService.changeWalletType();
        _walletCreationService.type = WalletType.wownero;
        // To restore from a seed
        final wallet = await _walletCreationService.create(credentials);
        //
        // final bufferedCreateHeight = (seedWordsLength == 14)
        //     ? getSeedHeightSync(wallet?.seed.trim() as String)
        //     : wownero.getHeightByDate(
        //     date: DateTime.now().subtract(const Duration(
        //         days:
        //         2))); // subtract a couple days to ensure we have a buffer for SWB
        final bufferedCreateHeight = getSeedHeightSync(wallet!.seed.trim());

        await info.updateRestoreHeight(
          newRestoreHeight: bufferedCreateHeight,
          isar: mainDB.isar,
        );

        // special case for xmr/wow. Normally mnemonic + passphrase is saved
        // before wallet.init() is called
        await secureStorageInterface.write(
          key: Wallet.mnemonicKey(walletId: walletId),
          value: wallet.seed.trim(),
        );
        await secureStorageInterface.write(
          key: Wallet.mnemonicPassphraseKey(walletId: walletId),
          value: "",
        );

        walletInfo.restoreHeight = bufferedCreateHeight;

        walletInfo.address = wallet.walletAddresses.address;
        await DB.instance
            .add<WalletInfo>(boxName: WalletInfo.boxName, value: walletInfo);

        wallet.close();
      } catch (e, s) {
        Logging.instance.log("$e\n$s", level: LogLevel.Fatal);
        CwBasedInterface.cwWalletBase?.close();
      }
      await updateNode();
    }

    return super.init();
  }

  @override
  Future<void> open() async {
    // await any previous exit
    await CwBasedInterface.exitMutex.protect(() async {});

    String? password;
    try {
      password = await cwKeysStorage.getWalletPassword(walletName: walletId);
    } catch (e, s) {
      throw Exception("Password not found $e, $s");
    }

    CwBasedInterface.cwWalletBase?.close();
    CwBasedInterface.cwWalletBase = (await CwBasedInterface.cwWalletService!
        .openWallet(walletId, password)) as WowneroWalletBase;

    (CwBasedInterface.cwWalletBase as WowneroWalletBase?)?.onNewBlock =
        onNewBlock;
    (CwBasedInterface.cwWalletBase as WowneroWalletBase?)?.onNewTransaction =
        onNewTransaction;
    (CwBasedInterface.cwWalletBase as WowneroWalletBase?)?.syncStatusChanged =
        syncStatusChanged;

    await updateNode();

    await (CwBasedInterface.cwWalletBase as WowneroWalletBase?)?.startSync();
    unawaited(refresh());
    autoSaveTimer?.cancel();
    autoSaveTimer = Timer.periodic(
      const Duration(seconds: 193),
      (_) async => await CwBasedInterface.cwWalletBase?.save(),
    );
  }

  @override
  Future<void> exitCwWallet() async {
    (CwBasedInterface.cwWalletBase as WowneroWalletBase?)?.onNewBlock = null;
    (CwBasedInterface.cwWalletBase as WowneroWalletBase?)?.onNewTransaction =
        null;
    (CwBasedInterface.cwWalletBase as WowneroWalletBase?)?.syncStatusChanged =
        null;
    await (CwBasedInterface.cwWalletBase as WowneroWalletBase?)
        ?.save(prioritySave: true);
  }

  @override
  Future<void> recover({required bool isRescan}) async {
    await CwBasedInterface.exitMutex.protect(() async {});

    if (isRescan) {
      await refreshMutex.protect(() async {
        // clear blockchain info
        await mainDB.deleteWalletBlockchainData(walletId);

        var restoreHeight =
            CwBasedInterface.cwWalletBase?.walletInfo.restoreHeight;
        highestPercentCached = 0;
        await CwBasedInterface.cwWalletBase?.rescan(height: restoreHeight ?? 0);
      });
      unawaited(refresh());
      return;
    }

    await refreshMutex.protect(() async {
      final mnemonic = await getMnemonic();
      final seedLength = mnemonic.trim().split(" ").length;

      if (!(seedLength == 14 || seedLength == 25)) {
        throw Exception("Invalid wownero mnemonic length found: $seedLength");
      }

      try {
        int height = info.restoreHeight;

        // extract seed height from 14 word seed
        if (seedLength == 14) {
          height = getSeedHeightSync(mnemonic.trim());
        } else {
          height = max(height, 0);
        }

        // TODO: info.updateRestoreHeight
        // await DB.instance
        //     .put<dynamic>(boxName: walletId, key: "restoreHeight", value: height);

        CwBasedInterface.cwWalletService = wow_dart.wownero
            .createWowneroWalletService(DB.instance.moneroWalletInfoBox);
        WalletInfo walletInfo;
        WalletCredentials credentials;
        String name = walletId;
        final dirPath =
            await pathForWalletDir(name: name, type: WalletType.wownero);
        final path = await pathForWallet(name: name, type: WalletType.wownero);
        credentials =
            wow_dart.wownero.createWowneroRestoreWalletFromSeedCredentials(
          name: name,
          height: height,
          mnemonic: mnemonic.trim(),
        );
        try {
          walletInfo = WalletInfo.external(
              id: WalletBase.idFor(name, WalletType.wownero),
              name: name,
              type: WalletType.wownero,
              isRecovery: false,
              restoreHeight: credentials.height ?? 0,
              date: DateTime.now(),
              path: path,
              dirPath: dirPath,
              // TODO: find out what to put for address
              address: '');
          credentials.walletInfo = walletInfo;

          final cwWalletCreationService = WalletCreationService(
            secureStorage: secureStorageInterface,
            walletService: CwBasedInterface.cwWalletService,
            keyService: cwKeysStorage,
          );
          cwWalletCreationService.type = WalletType.wownero;
          // To restore from a seed
          final wallet = await cwWalletCreationService
              .restoreFromSeed(credentials) as WowneroWalletBase;
          walletInfo.address = wallet.walletAddresses.address;
          await DB.instance
              .add<WalletInfo>(boxName: WalletInfo.boxName, value: walletInfo);
          CwBasedInterface.cwWalletBase?.close();
          CwBasedInterface.cwWalletBase = wallet;
          if (walletInfo.address != null) {
            final newReceivingAddress = await getCurrentReceivingAddress() ??
                Address(
                  walletId: walletId,
                  derivationIndex: 0,
                  derivationPath: null,
                  value: walletInfo.address!,
                  publicKey: [],
                  type: AddressType.cryptonote,
                  subType: AddressSubType.receiving,
                );

            await mainDB.updateOrPutAddresses([newReceivingAddress]);
            await info.updateReceivingAddress(
              newAddress: newReceivingAddress.value,
              isar: mainDB.isar,
            );
          }
        } catch (e, s) {
          Logging.instance.log("$e\n$s", level: LogLevel.Fatal);
        }
        await updateNode();

        await CwBasedInterface.cwWalletBase?.rescan(height: credentials.height);
        CwBasedInterface.cwWalletBase?.close();
      } catch (e, s) {
        Logging.instance.log(
            "Exception rethrown from recoverFromMnemonic(): $e\n$s",
            level: LogLevel.Error);
        rethrow;
      }
    });
  }

  @override
  Future<TxData> prepareSend({required TxData txData}) async {
    try {
      final feeRate = txData.feeRateType;
      if (feeRate is FeeRateType) {
        MoneroTransactionPriority feePriority;
        switch (feeRate) {
          case FeeRateType.fast:
            feePriority = MoneroTransactionPriority.fast;
            break;
          case FeeRateType.average:
            feePriority = MoneroTransactionPriority.regular;
            break;
          case FeeRateType.slow:
            feePriority = MoneroTransactionPriority.slow;
            break;
          default:
            throw ArgumentError("Invalid use of custom fee");
        }

        Future<PendingTransaction>? awaitPendingTransaction;
        try {
          // check for send all
          bool isSendAll = false;
          final balance = await availableBalance;
          if (txData.amount! == balance &&
              txData.recipients!.first.amount == balance) {
            isSendAll = true;
          }

          List<wownero_output.Output> outputs = [];
          for (final recipient in txData.recipients!) {
            final output =
                wownero_output.Output(CwBasedInterface.cwWalletBase!);
            output.address = recipient.address;
            output.sendAll = isSendAll;
            String amountToSend = recipient.amount.decimal.toString();
            output.setCryptoAmount(amountToSend);
            outputs.add(output);
          }

          final tmp =
              wow_dart.wownero.createWowneroTransactionCreationCredentials(
            outputs: outputs,
            priority: feePriority,
          );

          await prepareSendMutex.protect(() async {
            awaitPendingTransaction =
                CwBasedInterface.cwWalletBase!.createTransaction(tmp);
          });
        } catch (e, s) {
          Logging.instance.log("Exception rethrown from prepareSend(): $e\n$s",
              level: LogLevel.Warning);
        }

        PendingWowneroTransaction pendingWowneroTransaction =
            await (awaitPendingTransaction!) as PendingWowneroTransaction;
        final realFee = Amount.fromDecimal(
          Decimal.parse(pendingWowneroTransaction.feeFormatted),
          fractionDigits: cryptoCurrency.fractionDigits,
        );

        return txData.copyWith(
          fee: realFee,
          pendingWowneroTransaction: pendingWowneroTransaction,
        );
      } else {
        throw ArgumentError("Invalid fee rate argument provided!");
      }
    } catch (e, s) {
      Logging.instance.log("Exception rethrown from prepare send(): $e\n$s",
          level: LogLevel.Info);

      if (e.toString().contains("Incorrect unlocked balance")) {
        throw Exception("Insufficient balance!");
      } else if (e is CreationTransactionException) {
        throw Exception("Insufficient funds to pay for transaction fee!");
      } else {
        throw Exception("Transaction failed with error code $e");
      }
    }
  }

  @override
  Future<TxData> confirmSend({required TxData txData}) async {
    try {
      try {
        await txData.pendingWowneroTransaction!.commit();
        Logging.instance.log(
            "transaction ${txData.pendingWowneroTransaction!.id} has been sent",
            level: LogLevel.Info);
        return txData.copyWith(txid: txData.pendingWowneroTransaction!.id);
      } catch (e, s) {
        Logging.instance.log("${info.name} wownero confirmSend: $e\n$s",
            level: LogLevel.Error);
        rethrow;
      }
    } catch (e, s) {
      Logging.instance.log("Exception rethrown from confirmSend(): $e\n$s",
          level: LogLevel.Info);
      rethrow;
    }
  }

  @override
  Future<Amount> get availableBalance async {
    try {
      if (CwBasedInterface.exitMutex.isLocked) {
        throw Exception("Exit in progress");
      }

      int runningBalance = 0;
      for (final entry in (CwBasedInterface.cwWalletBase as WowneroWalletBase?)!
          .balance!
          .entries) {
        runningBalance += entry.value.unlockedBalance;
      }
      return Amount(
        rawValue: BigInt.from(runningBalance),
        fractionDigits: cryptoCurrency.fractionDigits,
      );
    } catch (_) {
      return info.cachedBalance.spendable;
    }
  }

  @override
  Future<Amount> get totalBalance async {
    try {
      if (CwBasedInterface.exitMutex.isLocked) {
        throw Exception("Exit in progress");
      }
      final balanceEntries =
          (CwBasedInterface.cwWalletBase as WowneroWalletBase?)
              ?.balance
              ?.entries;
      if (balanceEntries != null) {
        int bal = 0;
        for (var element in balanceEntries) {
          bal = bal + element.value.fullBalance;
        }
        return Amount(
          rawValue: BigInt.from(bal),
          fractionDigits: cryptoCurrency.fractionDigits,
        );
      } else {
        final transactions =
            CwBasedInterface.cwWalletBase!.transactionHistory!.transactions;
        int transactionBalance = 0;
        for (var tx in transactions!.entries) {
          if (tx.value.direction == TransactionDirection.incoming) {
            transactionBalance += tx.value.amount!;
          } else {
            transactionBalance += -tx.value.amount! - tx.value.fee!;
          }
        }

        return Amount(
          rawValue: BigInt.from(transactionBalance),
          fractionDigits: cryptoCurrency.fractionDigits,
        );
      }
    } catch (_) {
      return info.cachedBalance.total;
    }
  }
}
