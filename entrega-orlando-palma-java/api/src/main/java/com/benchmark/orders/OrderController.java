package com.benchmark.orders;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/orders")
public class OrderController {

    private final OrderService service;

    public OrderController(OrderService service) {
        this.service = service;
    }

    @PostMapping
    public ResponseEntity<?> create(@RequestBody(required = false) CreateOrderRequest request) {
        String error = validate(request);
        if (error != null) {
            return ResponseEntity.badRequest().body(Map.of("error", error));
        }
        return ResponseEntity.status(HttpStatus.CREATED).body(service.create(request));
    }

    /** Devuelve el mensaje de error, o null si la peticion es valida. */
    private static String validate(CreateOrderRequest request) {
        if (request == null) {
            return "el cuerpo de la peticion es requerido";
        }
        if (request.customerId() == null || request.customerId().isBlank()) {
            return "customerId es requerido";
        }
        List<OrderItem> items = request.items();
        if (items == null || items.isEmpty()) {
            return "items es requerido y no puede estar vacio";
        }
        for (OrderItem item : items) {
            if (item == null) {
                return "cada item debe ser un objeto";
            }
            if (item.productId() == null || item.productId().isBlank()) {
                return "productId es requerido en cada item";
            }
            if (item.quantity() == null || item.quantity() <= 0) {
                return "quantity debe ser un entero mayor que 0";
            }
            if (item.price() == null || item.price().compareTo(BigDecimal.ZERO) < 0) {
                return "price debe ser un numero mayor o igual que 0";
            }
        }
        return null;
    }
}
