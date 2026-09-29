extension Duration {
  /// The duration as fractional seconds.
  var inSeconds: Double {
    let parts = components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
  }
}
