import 'package:flutter/material.dart';
import 'package:kalium_wallet_flutter/appstate_container.dart';
import 'package:kalium_wallet_flutter/localization.dart';
import 'package:kalium_wallet_flutter/dimens.dart';
import 'package:kalium_wallet_flutter/bus/rxbus.dart';
import 'package:kalium_wallet_flutter/network/model/response/account_balance_item.dart';
import 'package:kalium_wallet_flutter/network/model/response/account_history_response.dart';
import 'package:kalium_wallet_flutter/network/model/response/pending_response.dart';
import 'package:kalium_wallet_flutter/network/model/response/pending_response_item.dart';
import 'package:kalium_wallet_flutter/ui/widgets/auto_resize_text.dart';
import 'package:kalium_wallet_flutter/ui/widgets/sheets.dart';
import 'package:kalium_wallet_flutter/ui/widgets/buttons.dart';
import 'package:kalium_wallet_flutter/ui/widgets/dialog.dart';
import 'package:kalium_wallet_flutter/ui/transfer/transfer_complete_sheet.dart';
import 'package:kalium_wallet_flutter/util/numberutil.dart';
import 'package:kalium_wallet_flutter/styles.dart';

class KaliumTransferConfirmSheet {
  // accounts to private keys/account balances
  Map<String, AccountBalanceItem> privKeyBalanceMap;
  // accounts that have all been pocketed and ready to send
  Map<String, AccountBalanceItem> readyToSendMap = Map();
  // Total amount there is to transfer
  BigInt totalToTransfer = BigInt.zero;
  String totalAsBanano = "";
  // Total amount transferred in raw
  BigInt totalTransferred = BigInt.zero;
  // Need to be received by current account
  PendingResponse accountPending;

  KaliumTransferConfirmSheet(this.privKeyBalanceMap);

  Future<bool> _onWillPop() async {
    RxBus.destroy(tag: RX_TRANSFER_ACCOUNT_HISTORY_TAG);
    RxBus.destroy(tag: RX_TRANSFER_PENDING_TAG);
    return true;
  }


  mainBottomSheet(BuildContext context) {
    // See how much we have to transfer and separate accounts with pendings
    privKeyBalanceMap.forEach((String account, AccountBalanceItem accountBalanceItem) {
      totalToTransfer += BigInt.parse(accountBalanceItem.balance) + BigInt.parse(accountBalanceItem.pending);
      if (BigInt.parse(accountBalanceItem.pending) == BigInt.zero && BigInt.parse(accountBalanceItem.balance) > BigInt.zero) {
        readyToSendMap.putIfAbsent(account, () => accountBalanceItem);
        privKeyBalanceMap.remove(account);
      } else if (BigInt.parse(accountBalanceItem.pending) == BigInt.zero && BigInt.parse(accountBalanceItem.balance) == BigInt.zero) {
        privKeyBalanceMap.remove(account);
      }
    });
    totalAsBanano = NumberUtil.getRawAsUsableString(totalToTransfer.toString());

    // Register event buses (this will probably get a little messy)
    // Receiving account history
    RxBus.register<AccountHistoryResponse>(tag: RX_TRANSFER_ACCOUNT_HISTORY_TAG).listen((AccountHistoryResponse historyResponse) {
      bool readyToSend = false;
      String account = historyResponse.account;
      AccountBalanceItem accountBalanceItem;
      if (!privKeyBalanceMap.containsKey(account)) {
        accountBalanceItem = readyToSendMap[account];
        readyToSend = true;
      } else {
        accountBalanceItem = privKeyBalanceMap[account];
      }
      if (historyResponse.history.length > 0) {
        accountBalanceItem.frontier = historyResponse.history.first.hash;
        if (readyToSend) {
          readyToSendMap[account] = accountBalanceItem;
        } else {
          privKeyBalanceMap[account] = accountBalanceItem;
        }
      }
      if (readyToSend) {
        startProcessing(context);
      } else {
        StateContainer.of(context).requestPending(account: account);
      }
    });
    // Pending response
    RxBus.register<PendingResponse>(tag: RX_PENDING_RESP_TAG).listen((pendingResponse) {
      // See if this is our account or a paper wallet account
      if (pendingResponse.account != StateContainer.of(context).wallet.address) {
        // TODO - null checking/error handling
        privKeyBalanceMap[pendingResponse.account].pendingResponse = pendingResponse;
        // Begin open/receive with pendings
        processNextPending(context, pendingResponse.account);
      } else {
        // Store result and start pocketing these
        accountPending = pendingResponse;
        processKaliumPending(StateContainer.of(context).wallet.address);
      }
    });

    KaliumSheets.showKaliumHeightNineSheet(
        context: context,
        onDisposed: _onWillPop,
        builder: (BuildContext context) {
          return StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
            return WillPopScope(
              onWillPop: _onWillPop,
                child: Container(
                width: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  children: <Widget>[
                    //A container for the header
                    Container(
                      margin: EdgeInsets.only(top: 30.0, left:70, right: 70),
                      child: AutoSizeText(
                        KaliumLocalization.of(context).transferHeader.toUpperCase(),
                        style: KaliumStyles.textStyleHeader(context),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        stepGranularity: 0.1,
                      ),
                    ),

                    // A container for the paragraphs
                    Expanded(
                      child: Container(
                        margin: EdgeInsets.only(top: MediaQuery.of(context).size.height*0.1),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Container(
                                margin: EdgeInsets.symmetric(horizontal: smallScreen(context)?35:60),
                                child: Text(
                                  KaliumLocalization.of(context).transferConfirmInfo.replaceAll("%1", totalAsBanano),
                                  style: KaliumStyles.TextStyleParagraphPrimary,
                                  textAlign: TextAlign.left,
                            )),
                            Container(
                                margin: EdgeInsets.symmetric(horizontal: smallScreen(context)?35:60),
                                child: Text(
                                  KaliumLocalization.of(context).transferConfirmInfoSecond,
                                  style: KaliumStyles.TextStyleParagraph,
                                  textAlign: TextAlign.left,
                            )),
                            Container(
                                margin: EdgeInsets.symmetric(horizontal: smallScreen(context)?35:60),
                                child: Text(
                                  KaliumLocalization.of(context).transferConfirmInfoThird,
                                  style: KaliumStyles.TextStyleParagraph,
                                  textAlign: TextAlign.left,
                            )),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      child: Column(
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              // Send Button
                              KaliumButton.buildKaliumButton(
                                  KaliumButtonType.PRIMARY,
                                  KaliumLocalization.of(context).confirm.toUpperCase(),
                                  Dimens.BUTTON_TOP_DIMENS, onPressed: () {
                                Navigator.of(context).push(AnimationLoadingOverlay(AnimationType.TRANSFER_TRANSFERRING));
                                startProcessing(context);
                              }),
                            ],
                          ),
                          Row(
                            children: <Widget>[
                              // Scan QR Code Button
                              KaliumButton.buildKaliumButton(
                                  KaliumButtonType.PRIMARY_OUTLINE,
                                  KaliumLocalization.of(context).cancel.toUpperCase(),
                                  Dimens.BUTTON_BOTTOM_DIMENS, onPressed: () {
                                Navigator.of(context).pop();
                              }),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          });
        });
  }

  ///
  /// processNextPending()
  ///
  /// Take the next pending block for this account and make a process request for an open/receive
  /// If there are no more pendings, move the account to "readyToSend" and begin processing next
  /// account.
  ///
  /// @param account
  ///
  void processNextPending(BuildContext context, String account) {
    AccountBalanceItem accountBalanceItem = privKeyBalanceMap[account];
    PendingResponse pendingResponse = accountBalanceItem.pendingResponse;
    Map<String, PendingResponseItem> pendingBlocks = pendingResponse.blocks;
    if (pendingBlocks.length  > 0) {
      String hash = pendingBlocks.keys.first;
      PendingResponseItem pendingItem = pendingBlocks.remove(hash);
      if (accountBalanceItem.frontier != null) {
        // Receive block
      } else {
        // Open account
      }
    } else {
      readyToSendMap.putIfAbsent(account, () => accountBalanceItem);
      privKeyBalanceMap.remove(account);
      startProcessing(context); // next account
    }
  }

  void processKaliumPending(String account) {

  }

  void startProcessing(BuildContext context) {
    if (privKeyBalanceMap.length > 0) {
      String account = privKeyBalanceMap.keys.first;
      //StateContainer.of(context).
    }
  }
}