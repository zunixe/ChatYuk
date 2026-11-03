import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'image_quality.dart';

/// Konversi frame image stream `camera` → `InputImage` ML Kit.
/// Android: nv21, iOS: bgra8888 (dulu iOS dilewati → kamera selfie KYC tak
/// pernah "siap" di iPhone). Format lain → null (lewati frame).
InputImage? cameraFrameToInputImage(
  CameraImage img,
  InputImageRotation rotation,
) {
  if (img.planes.isEmpty) return null;
  final InputImageFormat fmt;
  switch (img.format.group) {
    case ImageFormatGroup.nv21:
      fmt = InputImageFormat.nv21;
    case ImageFormatGroup.bgra8888:
      fmt = InputImageFormat.bgra8888;
    default:
      return null;
  }
  return InputImage.fromBytes(
    bytes: img.planes.first.bytes,
    metadata: InputImageMetadata(
      size: Size(img.width.toDouble(), img.height.toDouble()),
      rotation: rotation,
      format: fmt,
      bytesPerRow: img.planes.first.bytesPerRow,
    ),
  );
}

/// Kualitas frame (tajam/silau/gelap) di area tengah. null = format tak
/// didukung.
FrameQuality? cameraFrameQuality(CameraImage img) {
  if (img.planes.isEmpty) return null;
  final p = img.planes.first;
  switch (img.format.group) {
    case ImageFormatGroup.nv21:
    case ImageFormatGroup.yuv420:
      return FrameQuality.fromLuma(p.bytes, img.width, img.height, p.bytesPerRow);
    case ImageFormatGroup.bgra8888:
      return FrameQuality.fromBgra(p.bytes, img.width, img.height, p.bytesPerRow);
    default:
      return null;
  }
}

/// Rotasi InputImage dari orientasi sensor kamera.
InputImageRotation rotationForCamera(CameraDescription cam) =>
    InputImageRotationValue.fromRawValue(cam.sensorOrientation) ??
    InputImageRotation.rotation0deg;
