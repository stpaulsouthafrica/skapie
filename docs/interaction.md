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

Kit chrome (corners, border, header, type) is world-sized and multiplied by zoom. Zooming does not change a kit's proportions. Selection recolors that same border. It does not add a second stroke or resize the card. Every placeable kit has the same top bar: icon, then the kit name, then kit-specific detail on the right. Every kit corner radius is 8. LLM shows `select a model` or the model id, a play icon that runs the cabled Input, then Input, Context, Conversation, Tools, and Output. A tool shows the tool name. Text, box, and button are framed cards. A text kit shows its first line and then +N Lines, a grey rule, then In on the bottom left and Out on the bottom right. A Conversation kit uses that same preview, with Output on the bottom right. An LLM has nodes on Input, Context, Conversation, and Tools along the left edge, lined up with those labels. Output sits on the right of the last row, and Status sits on the left of that same row. A tool kit is one short row: Repository on the left when it needs one, and LLM on the right next to its node. Drag any node onto a compatible node, or use Allowed connections in the inspector. Hovering a draggable node changes the pointer; dragging its cable changes it again. Text cabled into Input is the prompt when you run. Text cabled into Context is sent as a system message. A Conversation kit cabled into Conversation is sent as earlier user and assistant turns. You add that kit yourself and cable it. Tools attach the same way as before. A Repository kit can cable into each repository tool's Repository input. An LLM output can cable into another LLM's Input or Context, or into a text kit. The LLM card shows the port labels Input, Context, Conversation, Tools, and Output. A port that can hold more than one cable shows its connection count, such as Tools · 2. The last row reads Status: Ready, Running, Waiting for review, Completed, Failed, or Cancelled, with Output on the right. Grey rules separate the ports. A handle on the bottom edge changes the card height, and the port rows and nodes spread to fill it. Hovering a tool shows its description, which the inspector can edit. A Repository kit labels its node In / Out. The inspector lists connected kit names, tool names, repository targets, permissions, availability, and last use. The reply, or the error, is written into each text kit cabled from Output. The cable takes the target kit's color. A text kit can cable into Input and Context at the same time, and a tool or LLM output can cable into more than one kit. Compatible ports only. Connecting, from a node or from Allowed connections, draws the cable with a short flash in the target kit's color. A cable made from the inspector grows with that flash instead of appearing all at once. The tool or text registers on the target kit only after the flash arrives, then fades in. A tool cable and its Repository cable pulse only while that tool is being called. Hover a cable and a scissor appears. Click cuts it, and the two ends retract into their ports. The LLM inspector's Request Information section is collapsed until opened. A chevron expands a short highlighted preview. A magnifying glass opens the same request full screen. Secrets stay redacted. Double-click a text kit to edit its text full screen. The palette does not offer system prompt, debug rect, or note card. Kit fill is panel gray at 85% opacity so the canvas dots show through. Swatches color the outline, rules, and shading. The inspector does not edit corner radius or opacity.

`locked == true`: still selectable and deletable; move is ignored. Toggle **Locked** in the inspector (`SetObjectLocked`); it is a scene-object field, not a prop.

Registry widgets stay `IgnorePointer`. Buttons do not receive Flutter taps. Hit-testing is done in the viewport from scene data.

## Move + undo

During drag, a **preview offset** lives on `SelectionController` (UI state). On pointer-up, **one** `SceneStore.apply(UpdateObjectFrame)` commits the final `x,y` for a normal object. A kit compound commits the same delta onto every member. Width/height are unchanged. Escape or pointer-cancel discards the preview.

## Inspector

Shown as a **floating overlay** on the right when something is selected. It does not reflow the canvas: viewport size, camera offset, and zoom stay put unless the user pans or zooms.

Selecting an LLM kit (frame or body) hosts the model, Run, and the attached Tools list in the inspector. The prompt is the text cabled into Input. An LLM kit has no Transform section. Kit color is one of ten swatches. Outline, rules, and shading follow that swatch. The card interior stays panel gray, slightly transparent. Selecting a `tools.*` kit shows Attach to that LLM's name / Detach. The name is colored with the LLM kit's accent. There is no bottom LLM bar. Sections are separated by hairlines. Buttons and fields wash with accent on hover. A kit has one identity: the first LLM is `LLM`, the next is `LLM (2)`. Edit Id in the inspector to rename it.

Hardcoded fields per `typeId`:

- `box`: fill, cornerRadius, opacity
- `text`: content, fontSize, color
- `button`: label
- `debug.rect` / unknown: type, id, frame; unknown also lists prop keys read-only

Edits use `UpdateObjectProps` or `UpdateObjectFrame` (submit or ~200ms debounce). **Locked** uses `SetObjectLocked`. Delete uses `RemoveObject` (whole kit compound when a kit member is selected). Inspector content does not rewrite the field while it is focused (avoids select-all wipe). Sync from the object when the selected id changes or the field unfocuses.
