package com.benchmark.orders;

import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

/** Calcula los totales del pedido y lo manda a guardar. */
@Service
public class OrderService {

    private final OrderRepository repository;

    public OrderService(OrderRepository repository) {
        this.repository = repository;
    }

    public CreateOrderResponse create(CreateOrderRequest request) {
        List<OrderItem> items = request.items();

        BigDecimal totalAmount = BigDecimal.ZERO;
        int itemsCount = 0;

        for (OrderItem item : items) {
            totalAmount = totalAmount.add(
                    item.price().multiply(BigDecimal.valueOf(item.quantity())));
            itemsCount += item.quantity();
        }
        // NUMERIC(10,2) en la tabla, asi que se redondea a 2 decimales.
        totalAmount = totalAmount.setScale(2, RoundingMode.HALF_UP);

        String orderId = "ORD-" + UUID.randomUUID();
        Instant processedAt = repository.save(orderId, request.customerId(), totalAmount, itemsCount, items);

        return new CreateOrderResponse(orderId, request.customerId(), totalAmount, itemsCount, processedAt);
    }
}
