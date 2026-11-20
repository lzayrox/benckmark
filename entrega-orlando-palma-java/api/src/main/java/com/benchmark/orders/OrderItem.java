package com.benchmark.orders;

import java.math.BigDecimal;

/**
 * Un item del pedido tal como llega en el JSON de entrada.
 * El precio se maneja como BigDecimal para no perder precision en el total.
 */
public record OrderItem(String productId, Integer quantity, BigDecimal price) {
}
