package com.benchmark.orders;

import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.Map;

/**
 * Convierte un JSON mal formado en un 400 con mensaje y un fallo de base de datos
 * en un 500 con mensaje. Cualquier otra excepcion se deja al manejo por defecto de
 * Spring, para no cambiar los codigos 404 y 405 por 500.
 */
@RestControllerAdvice
public class ApiExceptionHandler {

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<Map<String, String>> onUnreadableBody(HttpMessageNotReadableException ex) {
        return ResponseEntity.badRequest().body(Map.of("error", "el cuerpo no es un JSON valido"));
    }

    @ExceptionHandler(DataAccessException.class)
    public ResponseEntity<Map<String, String>> onDatabaseError(DataAccessException ex) {
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "no se pudo guardar el pedido"));
    }
}
