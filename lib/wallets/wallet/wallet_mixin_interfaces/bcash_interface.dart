import 'package:bitbox/bitbox.dart' as bitbox;
import 'package:isar/isar.dart';
import 'package:stackwallet/models/isar/models/blockchain_data/v2/input_v2.dart';
import 'package:stackwallet/models/isar/models/blockchain_data/v2/output_v2.dart';
import 'package:stackwallet/models/isar/models/blockchain_data/v2/transaction_v2.dart';
import 'package:stackwallet/models/isar/models/isar_models.dart';
import 'package:stackwallet/models/signing_data.dart';
import 'package:stackwallet/utilities/logger.dart';
import 'package:stackwallet/wallets/crypto_currency/crypto_currency.dart';
import 'package:stackwallet/wallets/models/tx_data.dart';
import 'package:stackwallet/wallets/wallet/intermediate/bip39_hd_wallet.dart';
import 'package:stackwallet/wallets/wallet/wallet_mixin_interfaces/electrumx_interface.dart';

mixin BCashInterface on Bip39HDWallet, ElectrumXInterface {
  @override
  Future<TxData> buildTransaction({
    required TxData txData,
    required List<SigningData> utxoSigningData,
  }) async {
    Logging.instance
        .log("Starting buildTransaction ----------", level: LogLevel.Info);

    // TODO: use coinlib

    final builder = bitbox.Bitbox.transactionBuilder(
      testnet: cryptoCurrency.network == CryptoCurrencyNetwork.test,
    );

    // temp tx data to show in gui while waiting for real data from server
    final List<InputV2> tempInputs = [];
    final List<OutputV2> tempOutputs = [];

    // Add transaction inputs
    for (int i = 0; i < utxoSigningData.length; i++) {
      builder.addInput(
        utxoSigningData[i].utxo.txid,
        utxoSigningData[i].utxo.vout,
      );

      tempInputs.add(
        InputV2.isarCantDoRequiredInDefaultConstructor(
          scriptSigHex: "000000",
          scriptSigAsm: null,
          sequence: 0xffffffff - 1,
          outpoint: OutpointV2.isarCantDoRequiredInDefaultConstructor(
            txid: utxoSigningData[i].utxo.txid,
            vout: utxoSigningData[i].utxo.vout,
          ),
          addresses: utxoSigningData[i].utxo.address == null
              ? []
              : [utxoSigningData[i].utxo.address!],
          valueStringSats: utxoSigningData[i].utxo.value.toString(),
          witness: null,
          innerRedeemScriptAsm: null,
          coinbase: null,
          walletOwns: true,
        ),
      );
    }

    // Add transaction output
    for (var i = 0; i < txData.recipients!.length; i++) {
      builder.addOutput(
        normalizeAddress(txData.recipients![i].address),
        txData.recipients![i].amount.raw.toInt(),
      );

      tempOutputs.add(
        OutputV2.isarCantDoRequiredInDefaultConstructor(
          scriptPubKeyHex: "000000",
          valueStringSats: txData.recipients![i].amount.raw.toString(),
          addresses: [
            txData.recipients![i].address.toString(),
          ],
          walletOwns: (await mainDB.isar.addresses
                  .where()
                  .walletIdEqualTo(walletId)
                  .filter()
                  .valueEqualTo(txData.recipients![i].address)
                  .or()
                  .valueEqualTo(normalizeAddress(txData.recipients![i].address))
                  .valueProperty()
                  .findFirst()) !=
              null,
        ),
      );
    }

    try {
      // Sign the transaction accordingly
      for (int i = 0; i < utxoSigningData.length; i++) {
        final bitboxEC = bitbox.ECPair.fromWIF(
          utxoSigningData[i].keyPair!.toWIF(),
        );

        builder.sign(
          i,
          bitboxEC,
          utxoSigningData[i].utxo.value,
        );
      }
    } catch (e, s) {
      Logging.instance.log("Caught exception while signing transaction: $e\n$s",
          level: LogLevel.Error);
      rethrow;
    }

    final builtTx = builder.build();
    final vSize = builtTx.virtualSize();

    return txData.copyWith(
      raw: builtTx.toHex(),
      vSize: vSize,
      tempTx: TransactionV2(
        walletId: walletId,
        blockHash: null,
        hash: builtTx.getId(),
        txid: builtTx.getId(),
        height: null,
        timestamp: DateTime.timestamp().millisecondsSinceEpoch ~/ 1000,
        inputs: List.unmodifiable(tempInputs),
        outputs: List.unmodifiable(tempOutputs),
        version: builtTx.version,
        type:
            tempOutputs.map((e) => e.walletOwns).fold(true, (p, e) => p &= e) &&
                    txData.paynymAccountLite == null
                ? TransactionType.sentToSelf
                : TransactionType.outgoing,
        subType: TransactionSubType.none,
        otherData: null,
      ),
    );
  }
}
