import 'package:flutter/foundation.dart';

/// Слой онлайн-оплаты. Сейчас подключена тестовая заглушка — реальные деньги
/// не списываются. Чтобы подключить провайдера (ЮKassa, CloudPayments, Stripe...),
/// реализуйте PaymentService и замените [paymentService] ниже.
///
/// Важно: подтверждать платёж нужно на сервере (webhook провайдера -> Supabase
/// Edge Function, которая ставит payment_status = 'paid'), а не с телефона.
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
