float calcFogFac(const float depth, const float maxVisible) {
  // return clamp(exp(-depth / maxVisible ) - 1.7, 0.0, 1.0);
  return clamp(depth * depth / (maxVisible * maxVisible) * 2.0 - 1.0, 0.0, 1.0);
}