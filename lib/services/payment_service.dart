import 'package:flutter/foundation.dart';

/// Слой онлайн-оплаты. Сейчас подключена тестовая заглушка — реальные деньги
/// не списываются. Чтобы подключить провайдера (ЮKassa, CloudPayments, Stripe...),
/// реализуйте PaymentService и замените [paymentService] ниже.
///
/// Важно: при подключении реального провайдера подтверждение платежа лучше
/// проверять на сервере (webhook), а не доверять только ответу приложения.
abstract class PaymentService {
  Future<bool> payForRide({required String rideId, required double amount});
}

class StubPaymentService implements PaymentService {
  @override
  Future<bool> payForRide({
    required String rideId,
    required double amount,
  }) async {
    debugPrint('[StubPayment] ride=$rideId amount=$amount');
    await Future<void>.delayed(const Duration(seconds: 1));
    return true;
  }
}

final PaymentService paymentService = StubPaymentService();
