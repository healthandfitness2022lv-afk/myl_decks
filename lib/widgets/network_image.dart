// lib/widgets/network_image.dart
// Imagen de red a prueba de fallos. Mismo uso que CachedNetworkImage.
// - Teléfono: CachedNetworkImage (caché en disco).
// - Web: el cargador estándar (caché del navegador). La caché propia de
//   cached_network_image dejaba descargas colgadas: cartas en negro. Si una
//   imagen no llega en 6 s o falla, prueba el proxy de respaldo y reintenta
//   (1 s, 2 s, 4 s…) hasta 5 rondas antes de mostrar el error.
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/drive_service.dart';

class MylNetworkImage extends StatelessWidget {
  const MylNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.placeholder,
    this.errorWidget,
    this.fadeInDuration,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Alignment alignment;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, Object)? errorWidget;
  final Duration? fadeInDuration;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        placeholder: placeholder,
        errorWidget: errorWidget,
        fadeInDuration: fadeInDuration ?? const Duration(milliseconds: 500),
      );
    }
    final urls = <String>[imageUrl];
    final respaldo = DriveService.proxyWeserv(imageUrl);
    if (respaldo.isNotEmpty && respaldo != imageUrl && !imageUrl.contains('images.weserv.nl')) {
      urls.add(respaldo);
    }
    return _ImagenWeb(
      key: ValueKey(imageUrl),
      urls: urls,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      placeholder: placeholder,
      errorWidget: errorWidget,
    );
  }
}

class _ImagenWeb extends StatefulWidget {
  const _ImagenWeb({
    super.key,
    required this.urls,
    this.width,
    this.height,
    this.fit,
    required this.alignment,
    this.placeholder,
    this.errorWidget,
  });

  final List<String> urls;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Alignment alignment;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, Object)? errorWidget;

  @override
  State<_ImagenWeb> createState() => _ImagenWebState();
}

class _ImagenWebState extends State<_ImagenWeb> {
  int _intento = 0; // ronda * direcciones + dirección
  bool _cargada = false;
  bool _rendida = false;
  Object _error = 'sin imagen';
  Timer? _timer;
  Timer? _plazo;

  String get _url => widget.urls[_intento % widget.urls.length];

  @override
  void dispose() {
    _timer?.cancel();
    _plazo?.cancel();
    super.dispose();
  }

  void _siguiente([Object? error]) {
    _plazo?.cancel();
    if (error != null) _error = error;
    if (!mounted || _cargada || _timer != null || _rendida) return;
    final siguiente = _intento + 1;
    if (siguiente >= widget.urls.length * 5) {
      setState(() => _rendida = true);
      return;
    }
    final ronda = siguiente ~/ widget.urls.length;
    final espera = siguiente % widget.urls.length == 0
        ? Duration(seconds: 1 << ronda.clamp(0, 4))
        : Duration.zero;
    _timer = Timer(espera, () {
      _timer = null;
      if (mounted) setState(() => _intento = siguiente);
    });
  }

  Widget _cargando(BuildContext context) =>
      widget.placeholder?.call(context, _url) ??
      SizedBox(width: widget.width, height: widget.height);

  @override
  Widget build(BuildContext context) {
    if (_rendida) {
      return widget.errorWidget?.call(context, _url, _error) ??
          SizedBox(width: widget.width, height: widget.height);
    }
    if (!_cargada) {
      // Una descarga colgada: a los 6 s se vuelve a pedir.
      _plazo?.cancel();
      _plazo = Timer(const Duration(seconds: 6), () {
        if (mounted && !_cargada) _siguiente('tiempo agotado');
      });
    }
    return Image.network(
      _url,
      key: ValueKey('$_url#$_intento'),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, _) {
        if (frame == null) return _cargando(context);
        if (!_cargada) {
          _cargada = true;
          _plazo?.cancel();
        }
        return child;
      },
      errorBuilder: (context, error, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _siguiente(error));
        return _cargando(context);
      },
    );
  }
}
