package com.benchmark.orders;

import java.util.List;

/** Cuerpo de la peticion POST /api/orders. */
public record CreateOrderRequest(String customerId, List<OrderItem> items) {
}
