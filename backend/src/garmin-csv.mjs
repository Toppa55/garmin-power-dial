const normalizeHeader = (value) => String(value ?? "").toLowerCase().replace(/[^a-z0-9]/g, "");

function parseRows(text, delimiter) {
  const rows = [];
  let row = [], field = "", quoted = false;
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    if (char === '"') {
      if (quoted && text[i + 1] === '"') { field += '"'; i++; }
      else quoted = !quoted;
    } else if (char === delimiter && !quoted) {
      row.push(field); field = "";
    } else if ((char === "\n" || char === "\r") && !quoted) {
      if (char === "\r" && text[i + 1] === "\n") i++;
      row.push(field); field = "";
      if (row.some((cell) => cell.trim())) rows.push(row);
      row = [];
    } else field += char;
  }
  if (quoted) throw new Error("Garmin Connect CSV has an unfinished quoted value");
  row.push(field);
  if (row.some((cell) => cell.trim())) rows.push(row);
  return rows;
}

function chooseDelimiter(text) {
  const header = text.split(/\r?\n/, 1)[0];
  return (header.match(/;/g) ?? []).length > (header.match(/,/g) ?? []).length ? ";" : ",";
}

function number(value) {
  const cleaned = String(value ?? "").replace(/,/g, "").replace(/[^0-9.\-]/g, "");
  const result = Number(cleaned);
  return cleaned && Number.isFinite(result) ? result : null;
}

function minutes(value) {
  const raw = String(value ?? "").trim();
  if (/^\d+(?::\d{1,2}){1,2}$/.test(raw)) {
    const parts = raw.split(":").map(Number);
    const seconds = parts.length === 3 ? parts[0] * 3600 + parts[1] * 60 + parts[2] : parts[0] * 60 + parts[1];
    return seconds / 60;
  }
  const duration = raw.match(/^(?:(\d+)h\s*)?(?:(\d+)m\s*)?(?:(\d+)s)?$/i);
  if (duration && duration[0]) return Number(duration[1] || 0) * 60 + Number(duration[2] || 0) + Number(duration[3] || 0) / 60;
  return number(raw);
}

function pick(row, headers, aliases) {
  for (const alias of aliases) {
    const index = headers.indexOf(normalizeHeader(alias));
    if (index >= 0 && row[index] != null && String(row[index]).trim()) return row[index];
  }
  return null;
}

export function parseGarminConnectCsv(text) {
  if (typeof text !== "string" || !text.trim()) throw new Error("Choose a Garmin Connect activities CSV file");
  const rows = parseRows(text.replace(/^\uFEFF/, ""), chooseDelimiter(text));
  if (rows.length < 2) throw new Error("Garmin Connect CSV contains no activities");
  const headers = rows.shift().map(normalizeHeader);
  if (!headers.includes("activitytype") || !headers.some((h) => ["avgpower", "averagepower", "averagepowerwatts"].includes(h))) {
    throw new Error("This does not look like a Garmin Connect activities CSV with power data");
  }
  const rides = [];
  let skipped = 0;
  for (const row of rows) {
    const type = String(pick(row, headers, ["Activity Type"]) ?? "").toLowerCase();
    const power = number(pick(row, headers, ["Avg Power", "Average Power", "Average Power Watts"]));
    const duration = minutes(pick(row, headers, ["Time", "Session Time", "Moving Time", "Duration"]));
    if (!/cycl|bike|ride|biking|virtual/.test(type) || !(power > 0 && power <= 1000) || !(duration > 0 && duration <= 1440)) { skipped++; continue; }
    const averageHr = number(pick(row, headers, ["Avg HR", "Average HR", "Average Heart Rate"]));
    const maxHr = number(pick(row, headers, ["Max HR", "Max Heart Rate"]));
    const normalizedPower = number(pick(row, headers, ["Normalized Power", "Norm Power", "NP"]));
    rides.push({
      started_at: pick(row, headers, ["Date", "Start Time", "Start Date"]),
      duration_minutes: duration,
      average_power_watts: power,
      normalized_power_watts: normalizedPower > 0 && normalizedPower <= 1200 ? normalizedPower : power,
      average_heart_rate_bpm: averageHr >= 30 && averageHr <= 240 ? averageHr : null,
      max_heart_rate_bpm: maxHr >= 30 && maxHr <= 250 ? maxHr : null,
      work_kj: power * duration * 60 / 1000
    });
  }
  if (!rides.length) throw new Error("No cycling rides with power and duration were found in the Garmin Connect CSV");
  if (rides.length > 5000) throw new Error("The CSV has more than 5000 powered cycling rides; split it by date before importing");
  return { rides, skipped, total: rows.length };
}
