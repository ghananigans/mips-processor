/*
 * MODULE: mips
 *
 * DESCRIPTION: Implementation of the 5 stages of a non-piplined
 *		MIPS Proceessor.
 *
 * PARAMETERS:
 *   pc_init [31:0]
 *     - Initial value for program counter.
 *   sp_init [31:0]
 *     - Initial value for stack pointer.
 *   ra_init [31:0]
 *     - Initial value for return address register.
 *
 * INPUTS:
 *   clk
 *     - Clock signal.
 *   reset
 *     - Reset signal.
 *   instr_in [31:0]
 *     - Input for data from instruction memory.
 *   data_in [31:0]
 *     - Input for data from data memory.
 *
 * OUTPUTS:
 *   data_rd_wr
 *     - Read or write signal for data memory.
 *   instr_addr [31:0]
 *     - Address for next instruction to be fetched from
 *       instruction memory/
 *   data_addr [31:0]
 *     - Address for the next data to be fetched or written to
 *       data memory.
 *   data_out [31:0]
 *     - Data output.
 */

enum bit [5:0] {
	SPECIAL  = 'b000000,
	J        = 'b000010,
	JAL      = 'b000011,
	BEQ      = 'b000100,
	BNE      = 'b000101,
	ADDIU    = 'b001001,
	SLTI     = 'b001010,
	SPECIAL2 = 'b011100,
	LW       = 'b100011,
	SW       = 'b101011
} MIPS_OPCODE;

enum bit [5:0] {
	SLL     = 'b000000,
	JR      = 'b001000,
	ADDU    = 'b100001,
	SUBU    = 'b100011,
	SLT     = 'b101010
} MIPS_SPECIAL_FUNCT_OPCODE;

enum bit [5:0] {
	MUL     = 'b000010
} MIPS_SPECIAL2_FUNCT_OPCODE;

enum bit [2:0] {
	ADD,
	SUB,
	MULTIPLY,
	SHIFT_LEFT_LOGICAL,
	LESS_THAN
} ALU_OP_TYPE;

module mips #(
	parameter [31:0] pc_init = 0,
	parameter [31:0] sp_init = 0,
	parameter [31:0] ra_init = 0
)(
	input wire clk, reset,
	input wire [31:0] instr_in, data_in,
	output wire data_rd_wr,
	output wire [31:0] data_out, data_addr,
	output reg [31:0] instr_addr
);
	reg [4:0] stage;

	// Fetch signals
	reg [31:0] f_pc, f_instruction_register;

	// Decode signals
	reg [31:0] d_pc, d_signed_extended_offset, d_rd0, d_rd1, d_jumping_target, d_branch_offset;
	reg [4:0] d_wb_register, d_shamt;
	// A (0: pc; 1: rs); B (0: rt; 1: offset)
	reg [1:0] d_muxA_sel, d_muxB_sel;
	reg d_m_data_sel, d_jumping, d_branch, d_rf_wr_en, d_data_rd_wr, d_wb_sel; // (d_wb_sel (0: alu_out, 1: mem_out))
	reg [2:0] d_ALU_sel;
	wire d_stall;
	wire [31:0] d_instruction_register;
	reg [31:0] d_branch_check_reg_a, d_branch_check_reg_b;

	// Execute stage
	reg e_rf_wr_en, e_data_rd_wr, e_m_data_sel, e_wb_sel;
	reg [4:0] e_wb_register;
	reg [31:0] e_alu_out, e_alu_out_comb, e_mem_data_to_store;
	reg [31:0] e_alu_iA, e_alu_iB;

	// Memory stage
	reg m_rf_wr_en, m_wb_sel;
	reg [4:0] m_wb_register;
	reg [31:0] m_alu_out;

	// Register File signals
	wire rf_wr_en;
	reg [4:0] rf_wr_num;
	wire [4:0] rf_rd0_num, rf_rd1_num;
	reg [31:0] rf_wr_data;
	wire [31:0] rf_rd0_data, rf_rd1_data;

	// This signal will be used to reset R31 (return address register)
	reg reset_return_address_register;

	regfile regs (
		.clk(clk),
		.wr_num(rf_wr_num),
		.wr_data(rf_wr_data),
		.wr_en(rf_wr_en),
		.rd0_num(rf_rd0_num),
		.rd1_num(rf_rd1_num),
		.rd0_data(rf_rd0_data),
		.rd1_data(rf_rd1_data)
	);

	always_ff @ (posedge clk)
	begin: MIPS
		if (reset == 1) begin
			// Reset Processor
			stage <= 'h0;

			// Reset the return address register in next clock cycle
			reset_return_address_register <= 1;
		end else if (reset_return_address_register == 1) begin
			reset_return_address_register <= 0;

			stage <= 'h1;
		end else  begin
			stage[4:1] <= stage[3:0];
			stage[0] <= 'h1;
		end
	end


	// FETCH
	always_comb
	begin : FETCH_COMB
		if (reset_return_address_register == 'b1 || d_stall == 1) begin
			instr_addr <= f_pc;
		end else if (d_jumping == 1) begin
			instr_addr <= d_jumping_target;
		end else if (d_branch == 1) begin
			instr_addr <= f_pc + d_branch_offset;
		end else begin
			instr_addr <= f_pc + 4;
		end

		/*instr_addr <= f_pc;*/
	end

	always_ff @ (posedge clk)
	begin : FETCH_FF
		if (reset == 'b1) begin
			// Reset PC
			f_pc <= pc_init;
			f_instruction_register <= 'h0;
		end else if (reset_return_address_register == 'b1) begin

		end else if (d_stall == 0) begin
			if (stage[0] == 1) begin
				f_instruction_register <= instr_in;
				f_pc <= instr_addr;
			end else begin
				f_instruction_register <= 'h0;
			end

			/*if (d_jumping == 1) begin
				f_pc <= d_jumping_target;
				f_instruction_register <= 'h0;
			end else if (d_branch == 1) begin
				f_pc <= f_pc + d_branch_offset;
				f_instruction_register <= 'h0;
			end else if (stage[0] == 1) begin
				f_pc <= f_pc + 'd4;
				f_instruction_register <= instr_in;
			end else begin
				f_instruction_register <= 'h0;
			end*/
		end
	end


	// DECODE

	// If previous instruction is a load and rs is a source operand for current instruction
	// but it is a wb register for the previous instruction, OR rt is being modified by previous
	// instruction and the current instruction is NOT a store word, stall.
	// Also stall if previous-previous instruction is a load word, and current instruction
	// is a possible branch depending on the data from load word.
	// BEQ = 000100 and BNE = 000101, so we only need to check if 5 MSB of opcode
	// equals 00010 to check if BEQ or BNE.
	assign d_stall = ((d_rf_wr_en == 1) && (d_data_rd_wr == 1) && (d_wb_sel == 1) && ((f_instruction_register[25:21] == d_wb_register) || ((f_instruction_register[20:16] == d_wb_register) && (f_instruction_register[31:26] != SW)))) || ((((e_rf_wr_en == 1) && (e_data_rd_wr == 1) && (e_wb_sel == 1) && ((f_instruction_register[25:21] == e_wb_register) || (f_instruction_register[20:16] == e_wb_register))) || ((d_rf_wr_en  == 1) && (d_wb_sel == 0) && ((f_instruction_register[25:21] == d_wb_register) || (f_instruction_register[20:16] == d_wb_register)) && (d_wb_register != 0) )) && (f_instruction_register[31:27] == 5'b00010));

	assign d_instruction_register = (d_stall == 1) ? 'h0 : f_instruction_register;
	assign rf_rd0_num = d_instruction_register[25:21]; // rs
	assign rf_rd1_num = d_instruction_register[20:16]; // rt

	always_comb
	begin
		if (e_rf_wr_en == 1 && e_wb_register == rf_rd0_num) begin
			d_branch_check_reg_a <= e_alu_out;
		end else if ((m_rf_wr_en == 1) && (m_wb_register == rf_rd0_num)) begin
			d_branch_check_reg_a <= rf_wr_data;
		end else begin
			d_branch_check_reg_a <= rf_rd0_data;
		end

		if (e_rf_wr_en == 1 && e_wb_register == rf_rd1_num) begin
			d_branch_check_reg_b <= e_alu_out;
		end else if ((m_rf_wr_en == 1) && (m_wb_register == rf_rd1_num)) begin
			d_branch_check_reg_b <= rf_wr_data;
		end else begin
			d_branch_check_reg_b <= rf_rd1_data;
		end
	end

	always_comb
	begin
		// determine branching/jumping
		case (d_instruction_register[31:26])
			SPECIAL: begin
				d_branch <= 0;

				case (d_instruction_register[5:0])
					JR: begin
						if ((m_rf_wr_en == 1) && (m_wb_register == rf_rd0_num)) begin
							d_jumping_target <= rf_wr_data;
						end else begin
							d_jumping_target <= rf_rd0_data;
						end

						d_jumping <= 1;
					end
					default: begin
						d_jumping <= 0;
					end
				endcase
			end
			J      : begin
				d_jumping_target <= {f_pc[31:28], d_instruction_register[25:0], 2'b00};

				d_jumping <= 1;
				d_branch <= 0;
			end
			JAL    : begin
				d_jumping_target <= {f_pc[31:28], d_instruction_register[25:0], 2'b00};

				d_jumping <= 1;
				d_branch <= 0;
			end
			BEQ    : begin
				d_branch_offset <= {{14{d_instruction_register[15]}}, d_instruction_register[15:0], 2'b00};

				d_jumping <= 0;
				d_branch <= d_branch_check_reg_a == d_branch_check_reg_b; // branch if rs == rt
			end
			BNE    : begin
				d_branch_offset <= {{14{d_instruction_register[15]}}, d_instruction_register[15:0], 2'b00};

				d_jumping <= 0;
				d_branch <= d_branch_check_reg_a != d_branch_check_reg_b; // branch if rs != rt
			end
			default : begin
				d_branch <= 0;
				d_jumping <= 0;
			end
		endcase
	end

	always_ff @ (posedge clk)
	begin : DECODE_FF
		if (reset == 1) begin
			// Reset
			d_rf_wr_en <= 0;
			d_data_rd_wr <= 1;
		end else if (reset_return_address_register == 1) begin

		end else begin
			d_pc <= f_pc;
			d_shamt <= d_instruction_register[10:6];

			if ((m_rf_wr_en == 1) && (m_wb_register == rf_rd0_num)) begin
				d_rd0 <= rf_wr_data;
			end else begin
				d_rd0 <= rf_rd0_data; // rs
			end

			if ((m_rf_wr_en == 1) && (m_wb_register == rf_rd1_num)) begin
				d_rd1 <= rf_wr_data;
			end else begin
				d_rd1 <= rf_rd1_data; // rt
			end

			case (d_instruction_register[31:26])
				SPECIAL : begin
					if (d_rf_wr_en == 1 && rf_rd0_num == d_wb_register) begin
						// Data forward from execute data back into execute input
						d_muxA_sel <= 2; // e_alu_out
					end else if (e_rf_wr_en == 1 && rf_rd0_num == e_wb_register) begin
						d_muxA_sel <= 3; // rf_wr_data
					end else begin
						d_muxA_sel <= 1; // rs
					end

					if (d_rf_wr_en == 1 && rf_rd1_num == d_wb_register) begin
						// Data forward from execute data back into execute input
						d_muxB_sel <= 2; // e_alu_out
					end else if (e_rf_wr_en == 1 && rf_rd1_num == e_wb_register) begin
						d_muxB_sel <= 3; // rf_wr_data
					end else begin
						d_muxB_sel <= 0; // rt
					end


					d_wb_register <= d_instruction_register[15:11]; // rd
					d_wb_sel <= 0;

					d_data_rd_wr <= 1; // no writing to mem

					case (d_instruction_register[5:0])
						SLL: begin
							d_ALU_sel <= SHIFT_LEFT_LOGICAL;
							d_signed_extended_offset <= {27'b0, d_instruction_register[10:6]};

							d_rf_wr_en <= 1;
						end
						ADDU   : begin
							d_ALU_sel <= ADD;

							d_rf_wr_en <= 1;
						end
						SUBU   : begin
							d_ALU_sel <= SUB;

							d_rf_wr_en <= 1;
						end
						SLT    : begin
							d_ALU_sel <= LESS_THAN;

							d_rf_wr_en <= 1;
						end
						default: begin
							d_rf_wr_en <= 0; // no updating reg file
						end
					endcase
				end
				JAL    : begin
					d_ALU_sel <= ADD;
					d_muxA_sel <= 0; // d_pc
					d_muxB_sel <= 1; // offset
					d_signed_extended_offset <= 32'd4;

					d_wb_register <= 'd31; // write to return address regiester
					d_wb_sel <= 0;

					d_data_rd_wr <= 1;
					d_rf_wr_en <= 1;
				end
				ADDIU  : begin
					d_ALU_sel <= ADD;

					if (d_rf_wr_en == 1 && rf_rd0_num == d_wb_register) begin
						// Data forward from execute data back into execute input
						d_muxA_sel <= 2; // e_alu_out
					end else if (e_rf_wr_en == 1 && rf_rd0_num == e_wb_register) begin
						d_muxA_sel <= 3; // rf_wr_data
					end else begin
						d_muxA_sel <= 1; // rs
					end

					d_muxB_sel <= 1; // offset
					d_signed_extended_offset <= {{16{d_instruction_register[15]}}, d_instruction_register[15:0]};

					d_wb_register <= d_instruction_register[20:16]; // rt
					d_wb_sel <= 0;

					d_data_rd_wr <= 1;
					d_rf_wr_en <= 1;
				end
				SLTI   : begin
					d_ALU_sel <= LESS_THAN;

					if (d_rf_wr_en == 1 && rf_rd0_num == d_wb_register) begin
						// Data forward from execute data back into execute input
						d_muxA_sel <= 2; // e_alu_out
					end else if (e_rf_wr_en == 1 && rf_rd0_num == e_wb_register) begin
						d_muxA_sel <= 3; // rf_wr_data
					end else begin
						d_muxA_sel <= 1; // rs
					end

					d_muxB_sel <= 1; // offset
					d_signed_extended_offset <= {{16{d_instruction_register[15]}}, d_instruction_register[15:0]};

					d_wb_register <= d_instruction_register[20:16]; // rt
					d_wb_sel <= 0;

					d_data_rd_wr <= 1;
					d_rf_wr_en <= 1;
				end
				SPECIAL2: begin
					if (d_rf_wr_en == 1 && rf_rd0_num == d_wb_register) begin
						// Data forward from execute data back into execute input
						d_muxA_sel <= 2; // e_alu_out
					end else if (e_rf_wr_en == 1 && rf_rd0_num == e_wb_register) begin
						d_muxA_sel <= 3; // rf_wr_data
					end else begin
						d_muxA_sel <= 1; // rs
					end

					if (d_rf_wr_en == 1 && rf_rd1_num == d_wb_register) begin
						// Data forward from execute data back into execute input
						d_muxB_sel <= 2; // e_alu_out
					end else if (e_rf_wr_en == 1 && rf_rd1_num == e_wb_register) begin
						d_muxB_sel <= 3; // rf_wr_data
					end else begin
						d_muxB_sel <= 0; // rt
					end

					d_wb_register <= d_instruction_register[15:11]; // rd
					d_wb_sel <= 0;

					d_data_rd_wr <= 1; // no write to mem

					case (d_instruction_register[5:0])
						MUL: begin
							d_ALU_sel <= MULTIPLY;

							d_rf_wr_en <= 1;
						end
						default   : begin
							d_rf_wr_en <= 0; // no updating reg file
						end
					endcase
				end
				LW     : begin
					d_ALU_sel <= ADD;

					if (d_rf_wr_en == 1 && rf_rd0_num == d_wb_register) begin
						// Data forward from execute data back into execute input
						d_muxA_sel <= 2; // e_alu_out
					end else if (e_rf_wr_en == 1 && rf_rd0_num == e_wb_register) begin
						d_muxA_sel <= 3; // rf_wr_data
					end else begin
						d_muxA_sel <= 1; // rs
					end

					d_muxB_sel <= 1; // offset
					d_signed_extended_offset <= {{16{d_instruction_register[15]}}, d_instruction_register[15:0]};

					d_wb_register <= d_instruction_register[20:16]; // rt
					d_wb_sel <= 1;

					d_data_rd_wr <= 1;
					d_rf_wr_en <= 1;
				end
				SW     : begin
					d_ALU_sel <= ADD;

					if (d_rf_wr_en == 1 && rf_rd0_num == d_wb_register) begin
						// Data forward from execute data back into execute input
						d_muxA_sel <= 2; // e_alu_out
					end else if (e_rf_wr_en == 1 && rf_rd0_num == e_wb_register) begin
						d_muxA_sel <= 3; // rf_wr_data
					end else begin
						d_muxA_sel <= 1; // rs
					end

					if (d_rf_wr_en == 1 && rf_rd1_num == d_wb_register) begin
						// Store added data right after an add op. (ADDIU v0, v1, v2 then SW v0, 0(sp))
						d_m_data_sel <= 0;
					end else begin
						d_m_data_sel <= 1;
					end

					d_muxB_sel <= 1; // offset
					d_signed_extended_offset <= {{16{d_instruction_register[15]}}, d_instruction_register[15:0]};

					d_data_rd_wr <= 0;
					d_rf_wr_en <= 0;
				end
				default: begin
					d_data_rd_wr <= 1; // no write to mem
					d_rf_wr_en <= 0; // no updating reg file
				end
			endcase
		end
	end


	// EXECUTE
	always_comb
	begin : EXECUTE_INPUTS
		case (d_muxA_sel)
			0 : e_alu_iA <= d_pc;
			1 : e_alu_iA <= d_rd0;
			2 : e_alu_iA <= e_alu_out;
			3 : e_alu_iA <= rf_wr_data;
			default : e_alu_iA <= 'h0;
		endcase

		case (d_muxB_sel)
			0 : e_alu_iB <= d_rd1;
			1 : e_alu_iB <= d_signed_extended_offset;
			2 : e_alu_iB <= e_alu_out;
			3 : e_alu_iB <= rf_wr_data;
			default : e_alu_iB <= 'h0;
		endcase
	end

	always_comb
	begin : EXECUTE_ALU
		case (d_ALU_sel)
			ADD                 : e_alu_out_comb <= e_alu_iA + e_alu_iB;
			SUB                 : e_alu_out_comb <= e_alu_iA - e_alu_iB;
			MULTIPLY            : e_alu_out_comb <= e_alu_iA * e_alu_iB;
			SHIFT_LEFT_LOGICAL  : e_alu_out_comb <= e_alu_iB << d_shamt;
			LESS_THAN           : e_alu_out_comb <= e_alu_iA < e_alu_iB;
			default             : e_alu_out_comb <= 'd0;
		endcase
	end

	always_ff @ (posedge clk)
	begin : EXECUTE_FF
		e_rf_wr_en <= ~reset & ~reset_return_address_register & d_rf_wr_en;
		e_data_rd_wr <= reset | reset_return_address_register| d_data_rd_wr;
		e_wb_sel <= d_wb_sel;
		e_mem_data_to_store <= d_rd1;
		e_m_data_sel <= d_m_data_sel;
		e_wb_register <= d_wb_register;
		e_alu_out <= e_alu_out_comb;
	end


	// MEMORY
	assign data_addr = e_alu_out;
	assign data_out = (e_m_data_sel == 1) ? e_mem_data_to_store : rf_wr_data;
	assign data_rd_wr = reset | reset_return_address_register | e_data_rd_wr;

	always_ff @ (posedge clk)
	begin : MEMORY_FF
		m_rf_wr_en <= ~reset & ~reset_return_address_register & e_rf_wr_en;
		m_alu_out <= e_alu_out;
		m_wb_sel <= e_wb_sel;
		m_wb_register <= e_wb_register;
	end


	// WRITEBACK
	assign rf_wr_en = reset | reset_return_address_register | m_rf_wr_en;

	always_comb
	begin : WRITEBACK_COMB
		if (reset == 1) begin
			rf_wr_num <= 'd29;
			rf_wr_data <= sp_init;
		end else if (reset_return_address_register == 1) begin
			rf_wr_num <= 'd31;
			rf_wr_data <= ra_init;
		end else begin
			rf_wr_num <= m_wb_register;
			rf_wr_data <= (m_wb_sel == 1) ? data_in : m_alu_out;
		end
	end

endmodule
