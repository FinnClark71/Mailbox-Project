package msg_desc_pkg;

  // Central place to define descriptor widths / formats
  parameter int DEST_W = 4;   // 16 threads
  parameter int LEN_W  = 8;   // message length metadata
  parameter int SLOT_W = 8;   // scratchpad slot id

  localparam int TX_W = DEST_W + LEN_W + SLOT_W; // {dest,len,slot} tx
  localparam int RX_W = LEN_W  + SLOT_W;         // {len,slot} rx

  typedef logic [DEST_W-1:0] dest_t;
  typedef logic [LEN_W-1:0]  len_t;
  typedef logic [SLOT_W-1:0] slot_t;

  typedef logic [TX_W-1:0]   tx_desc_t;
  typedef logic [RX_W-1:0]   rx_desc_t;

  // TX descriptor: {dest, len, slot}
  function automatic tx_desc_t pack_tx_desc(dest_t dest, len_t len, slot_t slot);
    pack_tx_desc = {dest, len, slot};
  endfunction

  function automatic dest_t tx_get_dest(tx_desc_t d);
    tx_get_dest = d[TX_W-1 -: DEST_W];
  endfunction

  function automatic len_t tx_get_len(tx_desc_t d);
    tx_get_len = d[SLOT_W+LEN_W-1 -: LEN_W];
  endfunction

  function automatic slot_t tx_get_slot(tx_desc_t d);
    tx_get_slot = d[SLOT_W-1:0];
  endfunction

  // RX descriptor: {len, slot}
  function automatic rx_desc_t pack_rx_desc(len_t len, slot_t slot);
    pack_rx_desc = {len, slot};
  endfunction

  function automatic len_t rx_get_len(rx_desc_t d);
    rx_get_len = d[RX_W-1 -: LEN_W];
  endfunction

  function automatic slot_t rx_get_slot(rx_desc_t d);
    rx_get_slot = d[SLOT_W-1:0];
  endfunction

  // Conversion helpers (e.g. from TX to RX when “delivered”)
  function automatic rx_desc_t tx_to_rx_desc(tx_desc_t txd);
    tx_to_rx_desc = pack_rx_desc(tx_get_len(txd), tx_get_slot(txd));
  endfunction

endpackage
