.pragma library
const styles = [
    { id: "notch", label: "Notch",
      bar: { notchStyle: "classic", corners: "round", endCurve: 16, flatIsland: false } },
    { id: "trapezoid", label: "Trapezoid",
      bar: { notchStyle: "slant", corners: "round", endCurve: 16, flatIsland: false } },
    { id: "flat", label: "Flat",
      bar: { notchStyle: "classic", corners: "round", endCurve: 16, flatIsland: true } },
];

function current(bar) {
    const s = styles.find(s => Object.keys(s.bar).every(k => bar[k] === s.bar[k]));
    return s ? s.id : "";
}

function apply(bar, id) {
    const s = styles.find(s => s.id === id);
    for (const k in s.bar) bar[k] = s.bar[k];
}

function preview(id) {
    const bar = styles.find(s => s.id === id).bar, square = bar.corners === "square";
    return {
        style: bar.notchStyle, square: square, notchCorner: square ? 0 : 4,
        radius: square ? 0 : 10, flat: bar.flatIsland,
    };
}
