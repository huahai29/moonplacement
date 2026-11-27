///|
pub const INPUT_FILE_MAX_BYTES : Int32 = 8_388_608

///|
pub const POLICY_FILE_MAX_BYTES : Int32 = 65_536

///|
pub const INPUT_ERROR_EXIT_CODE : Int32 = 64

///|
/// Process exit status for a completed audit.
pub fn Verdict::exit_code(self : Verdict) -> Int32 {
  match self {
    Pass => 0
    Different => 1
    Indeterminate => 2
  }
}

///|
/// Format a source or configuration error for a CLI or browser host.
pub fn input_error_report(field : String, message : String) -> Json {
  {
    "schema_version": Json(REPORT_SCHEMA_VERSION),
    "status": Json("input_error"),
    "field": Json(field),
    "message": Json(message),
  }
}

///|
fn contract_type(name : String) -> Json {
  { "type": Json(name) }
}

///|
fn contract_enum(values : Array[String]) -> Json {
  { "enum": Json(values) }
}

///|
fn contract_items(items : Json) -> Json {
  { "type": Json("array"), "items": items }
}

///|
fn contract_object(properties : Json, optional~ : Array[String] = []) -> Json {
  let required = match properties {
    Object(fields) =>
      fields.keys().filter(key => !optional.contains(key)).collect()
    _ => abort("contract property definition must be an object")
  }
  {
    "type": Json("object"),
    "required": Json(required),
    "properties": properties,
  }
}

///|
fn contract_ref(name : String) -> Json {
  { "$ref": Json("#/$defs/" + name) }
}

///|
/// JSON Schema for audit and input-error reports. Extension metadata gives
/// the exit statuses and host-side UTF-8 input limits.
pub fn report_contract() -> Json {
  let verdicts = [Pass, Different, Indeterminate]
  let exit_codes : Map[String, Json] = Map([])
  for verdict in verdicts {
    exit_codes[verdict_name(verdict)] = Json(verdict.exit_code())
  }
  exit_codes["input_error"] = Json(INPUT_ERROR_EXIT_CODE)
  let text = contract_type("string")
  let number = contract_type("number")
  let integer = contract_type("integer")
  let boolean = contract_type("boolean")
  let object = contract_type("object")
  let nullable_string : Json = { "type": ["string", "null"] }
  let side = contract_enum(["top", "bottom"])
  let schema_version : Json = { "const": Json(REPORT_SCHEMA_VERSION) }
  let reference_kind = contract_object({ "ref": text, "kind": text })
  let pad_difference = contract_object({
    "ref": text,
    "kind": { "const": Json("pad_offset") },
    "delta_x_mm": number,
    "delta_y_mm": number,
    "distance_mm": number,
  })
  let panel_cell = contract_object({
    "side": side,
    "row": integer,
    "column": integer,
    "rows": integer,
    "columns": integer,
    "offset_x_mm": number,
    "offset_y_mm": number,
  })
  let pad_origin = contract_object(
    {
      "status": contract_enum(["corrected", "review", "pose_mismatch"]),
      "matched_by": contract_enum(["ref", "footprint"]),
      "source": text,
      "raw_distance_mm": number,
      "raw_delta_x_mm": number,
      "raw_delta_y_mm": number,
      "applied_dx_mm": number,
      "applied_dy_mm": number,
    },
    optional=["applied_dx_mm", "applied_dy_mm"],
  )
  let pad_evidence_details = contract_object(
    {
      "status": contract_enum(["by_reference", "copper_only", "unverified"]),
      "reason": text,
      "pad_count": integer,
      "distance_mm": number,
      "within_tolerance": boolean,
      "origin": pad_origin,
    },
    optional=[
      "reason", "pad_count", "distance_mm", "within_tolerance", "origin",
    ],
  )
  let pad_evidence = contract_object({
    "ref": text,
    "side": side,
    "evidence": pad_evidence_details,
  })
  let pad_warning = contract_object({ "side": side, "message": text })
  let pad_layer_properties : Json = {
    "side": side,
    "status": contract_enum(["complete", "incomplete", "failed", "skipped"]),
    "checked": integer,
    "targets": integer,
    "message": text,
  }
  let table_import = contract_object({
    "x_column": text,
    "y_column": text,
    "footprint_prefix": text,
    "excluded_refs": contract_items(text),
  })
  let audit_properties : Json = {
    "schema_version": schema_version,
    "status": contract_enum(verdicts.map(verdict_name)),
    "reason": nullable_string,
    "frame": { "type": ["object", "null"] },
    "candidate_frames": contract_items(object),
    "rejected_frames": contract_items(object),
    "anchors": contract_items(text),
    "anchor_issues": contract_items(reference_kind),
    "baseline_count": integer,
    "delivery_count": integer,
    "baseline_coordinates": contract_object({
      "unit": contract_enum(["mm", "in", "mil"]),
      "bottom_x": contract_enum(["direct", "negated"]),
    }),
    "differences": contract_items(reference_kind),
    "pad_differences": contract_items(pad_difference),
    "pad_checked": integer,
    "pad_skipped": boolean,
    "pad_status": contract_enum([
      "not_requested", "skipped", "incomplete", "complete",
    ]),
    "pad_sides": contract_items(side),
    "panel_cells": contract_items(panel_cell),
    "pad_evidence": contract_items(pad_evidence),
    "pad_warnings": contract_items(pad_warning),
    "pad_layers": contract_items(
      contract_object(pad_layer_properties, optional=["message"]),
    ),
    "placement_import": contract_object({
      "scope": contract_enum(["all", "expected", "excluded"]),
      "baseline": table_import,
      "delivery": table_import,
    }),
    "tolerances": contract_object({
      "position_mm": number,
      "angle_deg": number,
      "anchor_mm": number,
      "pad_mm": number,
    }),
  }
  let audit = contract_object(audit_properties, optional=[
    "baseline_coordinates", "placement_import", "pad_layers",
  ])
  let input_error = contract_object({
    "schema_version": schema_version,
    "status": { "const": Json("input_error") },
    "field": text,
    "message": text,
  })
  {
    "$schema": Json("https://json-schema.org/draft/2020-12/schema"),
    "title": Json("MoonPlacement report"),
    "oneOf": [contract_ref("audit"), contract_ref("input_error")],
    "$defs": { "audit": audit, "input_error": input_error },
    "x-moonplacement-exit-codes": Json::object(exit_codes),
    "x-moonplacement-input-bytes": {
      "placement": Json(INPUT_FILE_MAX_BYTES),
      "gerber": Json(INPUT_FILE_MAX_BYTES),
      "policy": Json(POLICY_FILE_MAX_BYTES),
    },
  }
}
