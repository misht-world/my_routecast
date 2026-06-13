package com.routecast.parse

/** Понятная ошибка разбора входного файла (битый/пустой/без геометрии) — не краш. */
class RouteParseException(message: String) : Exception(message)
