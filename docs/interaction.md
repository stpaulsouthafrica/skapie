# Interaction (select, move, edit)

Selection, move, and inspector edits are UI. The scene document stays the source of truth. Selection is **not** written to `scene.json`. Reload starts with no selection.

## Gestures

- **Primary down on an object:** select it (topmost visible AABB hit). If unlocked, start a move drag.
- **Primary down on empty canvas:** clear selection and pan the camera (existing pan).
- **Middle mouse (button 2) down + drag:** pan the camera. Does not select or move objects, even over a hit.
- **Trackpad pan / scroll / pinch zoom:** unchanged. Zoom still aims at the cursor.
- While move-dragging, the camera does not pan.
- **Escape:** cancel an in-progress move preview, otherwise clear selection. If the command palette is open, Escape closes it instead.
- **Space / F3:** open the command palette when the canvas has focus and the user is not typing in a text field. Hovering a row and Up/Down (optional Ctrl-N/P) share one highlight; Enter runs the highlight; click runs that row; Esc closes. Search keeps focus.
- **LLM compound drag:** dragging any part of `harness.llm` (frame or body) moves both members by the same delta. The body is not a free-floating note.
- **Double-click** a non-LLM `text` object: inline edit on the canvas (caret in world). Esc or unfocus saves through KitApi. Single-click still selects and shows the inspector.
- **Delete / Backspace:** `RemoveObject` when the canvas has focus (inspector text fields keep those keys).

Hit-test is world-space AABB from `x,y,width,height`. **Rotation is ignored** (same as camera content bounds). Invisible objects are skipped. Highest `zIndex` wins; later list order breaks ties.

`locked == true`: still selectable and deletable; move is ignored. Toggle **Locked** in the inspector (`SetObjectLocked`); it is a scene-object field, not a prop.

Registry widgets stay `IgnorePointer`. Buttons do not receive Flutter taps. Hit-testing is done in the viewport from scene data.

## Move + undo

During drag, a **preview offset** lives on `SelectionController` (UI state). On pointer-up, **one** `SceneStore.apply(UpdateObjectFrame)` commits the final `x,y` for a normal object. An LLM compound commits the same delta onto frame and body. Width/height are unchanged. Escape or pointer-cancel discards the preview.

## Inspector

Shown as a **floating overlay** on the right when something is selected. It does not reflow the canvas: viewport size, camera offset, and zoom stay put unless the user pans or zooms.

Selecting an LLM kit (frame or body) hosts model, Input, read-only Output, Run, and the attached Tools list in the inspector. Selecting a `tools.*` kit shows Attach to LLM / Detach. There is no bottom LLM bar.

Hardcoded fields per `typeId`:

- `box`: fill, cornerRadius, opacity
- `text`: content, fontSize, color
- `button`: label
- `debug.rect` / unknown: type, id, frame; unknown also lists prop keys read-only

Edits use `UpdateObjectProps` or `UpdateObjectFrame` (submit or ~200ms debounce). **Locked** uses `SetObjectLocked`. Delete uses `RemoveObject`. Inspector content does not rewrite the field while it is focused (avoids select-all wipe). Sync from the object when the selected id changes or the field unfocuses.
