package com.benchmark.orders;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;

/**
 * Acceso a datos del pedido. Las dos inserciones (orders y order_items) se hacen
 * dentro de UNA sola transaccion: @Transactional toma una conexion del pool de
 * HikariCP, la usa para todo el metodo y hace COMMIT al salir o ROLLBACK si se
 * lanza una excepcion.
 */
@Repository
public class OrderRepository {

    private static final String INSERT_ORDER = """
            INSERT INTO orders (order_id, customer_id, total_amount, items_count)
            VALUES (?, ?, ?, ?)
            RETURNING created_at
            """;

    private static final String INSERT_ITEM = """
            INSERT INTO order_items (order_id, product_id, quantity, price)
            VALUES (?, ?, ?, ?)
            """;

    private final JdbcTemplate jdbcTemplate;

    public OrderRepository(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @Transactional
    public Instant save(String orderId,
                        String customerId,
                        BigDecimal totalAmount,
                        int itemsCount,
                        List<OrderItem> items) {

        Timestamp createdAt = jdbcTemplate.queryForObject(
                INSERT_ORDER, Timestamp.class,
                orderId, customerId, totalAmount, itemsCount);

        // Todos los items en un solo viaje a la base de datos.
        jdbcTemplate.batchUpdate(INSERT_ITEM, items, items.size(), (ps, item) -> {
            ps.setString(1, orderId);
            ps.setString(2, item.productId());
            ps.setInt(3, item.quantity());
            ps.setBigDecimal(4, item.price());
        });

        return createdAt != null ? createdAt.toInstant() : Instant.now();
    }
}
