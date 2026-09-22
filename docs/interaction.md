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
- **LLM compound drag:** dragging any part of a `skapieKit` instance (LLM or `tools.*`) moves the whole group. The body is not a free-floating note.
- **Double-click** a non-kit `text` object: inline edit on the canvas (caret in world). Esc or unfocus saves through KitApi. Single-click still selects and shows the inspector.
- **Delete / Backspace:** removes the selected object, or the whole kit compound when a kit member is selected. Inspector Delete does the same.

Hit-test is world-space AABB from `x,y,width,height`. **Rotation is ignored** (same as camera content bounds). Invisible objects are skipped. Highest `zIndex` wins; later list order breaks ties.

Kit chrome (corners, border, header, type) is world-sized and multiplied by zoom. Zooming does not change a kit's proportions. Selection recolors that same border. It does not add a second stroke or resize the card. Every placeable kit has the same top bar: icon, then the kit name, then kit-specific detail on the right. Every kit corner radius is 8. LLM shows `select a model` or the model id, then Input, Context, Tools, and Output. A tool shows the tool name. Text, box, and button are framed cards. A text kit says Output and has an output node on the bottom right. An LLM has nodes on Input, Context, and Tools (left) and Output (right), lined up with those labels. A tool kit has an output node on the right. Drag an output node onto a matching input, or use Allowed connections in the inspector. Text cabled into Input is the prompt when you run. Context lists cabled text and does not change the run. Tools attach the same way as before. An LLM output can cable into another LLM's Input or Context. The cable takes the target kit's color. Double-click a text kit to edit its text in place. The palette does not offer system prompt, debug rect, or note card. Kit fill is panel gray at 85% opacity so the canvas dots show through. Swatches color the outline, rules, and shading. The inspector does not edit corner radius or opacity.

`locked == true`: still selectable and deletable; move is ignored. Toggle **Locked** in the inspector (`SetObjectLocked`); it is a scene-object field, not a prop.

Registry widgets stay `IgnorePointer`. Buttons do not receive Flutter taps. Hit-testing is done in the viewport from scene data.

## Move + undo

During drag, a **preview offset** lives on `SelectionController` (UI state). On pointer-up, **one** `SceneStore.apply(UpdateObjectFrame)` commits the final `x,y` for a normal object. A kit compound commits the same delta onto every member. Width/height are unchanged. Escape or pointer-cancel discards the preview.

## Inspector

Shown as a **floating overlay** on the right when something is selected. It does not reflow the canvas: viewport size, camera offset, and zoom stay put unless the user pans or zooms.

Selecting an LLM kit (frame or body) hosts model, Input, read-only Output, Run, and the attached Tools list in the inspector. Kit color is one of ten swatches. Outline, rules, and shading follow that swatch. The card interior stays panel gray, slightly transparent. Selecting a `tools.*` kit shows Attach to that LLM's name / Detach. The name is colored with the LLM kit's accent. There is no bottom LLM bar. Sections are separated by hairlines. Buttons and fields wash with accent on hover. A kit has one identity: the first LLM is `LLM`, the next is `LLM (2)`. Edit Id in the inspector to rename it.

Hardcoded fields per `typeId`:

- `box`: fill, cornerRadius, opacity
- `text`: content, fontSize, color
- `button`: label
- `debug.rect` / unknown: type, id, frame; unknown also lists prop keys read-only

Edits use `UpdateObjectProps` or `UpdateObjectFrame` (submit or ~200ms debounce). **Locked** uses `SetObjectLocked`. Delete uses `RemoveObject` (whole kit compound when a kit member is selected). Inspector content does not rewrite the field while it is focused (avoids select-all wipe). Sync from the object when the selected id changes or the field unfocuses.
