package com.benchmark.orders;

import java.math.BigDecimal;
import java.time.Instant;

/** Respuesta HTTP 201 con el resumen del pedido guardado. */
public record CreateOrderResponse(
        String orderId,
        String customerId,
        BigDecimal totalAmount,
        int itemsCount,
        Instant processedAt) {
}
