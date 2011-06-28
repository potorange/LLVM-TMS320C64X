//===- TMS320C64XInstrFormats.td - TMS320C64X Insn formats -*- tablegen -*-===//
//
// Copyright 2010 Jeremy Morse <jeremy.morse@gmail.com>. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY JEREMY MORSE ``AS IS'' AND ANY EXPRESS OR
// IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
// OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
// IN NO EVENT SHALL JEREMY MORSE OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
// INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
// THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//===----------------------------------------------------------------------===//

class UnitSupport<bit l, bit s, bit m, bit d> {
  bits<4> units = { d, m, s, l };
}

def units_fixed : UnitSupport<0,0,0,0>;
def units_any   : UnitSupport<1,1,1,1>;
def units_s     : UnitSupport<0,1,0,0>;
def units_m     : UnitSupport<0,0,1,0>;
def units_d     : UnitSupport<0,0,0,1>;
def units_notm  : UnitSupport<1,1,0,1>;

class Delay<bits<3> val> {
  bits<3> value = val;
}

class InstUnit<bits<2> u> {
  bits<2> unit = u;
}

def unit_l      : InstUnit<0>;
def unit_s      : InstUnit<1>;
def unit_m      : InstUnit<2>;
def unit_d      : InstUnit<3>;

// here is me not being able to cast int to bit...
class InstSide<int si, bit sb> {
  int intval = si;
  bit bitval = sb;
}

def side_a : InstSide<0,0>;
def side_b : InstSide<1,1>;

def mem_operand	: Operand<i32> {
	let PrintMethod = "printMemOperand";
	let MIOperandInfo = (ops GPRegs, GPRegs);
}

def calltarget : Operand<i32>;
def brtarget : Operand<OtherVT>;
def call_ret_label_operand_operand : Operand<i32> {
	let PrintMethod = "printRetLabel";
}

// NKIM, for the time being we require the root-node to be supplied
def addr : ComplexPattern<i32, 2, "select_addr", [], [SDNPWantRoot]>;
def idxaddr : ComplexPattern<i32, 2, "select_idxaddr", [frameindex], [SDNPWantRoot]>;

def uconst4_xform : SDNodeXForm<imm, [{
	return CurDAG->getTargetConstant((int)N->getSExtValue(), MVT::i32);
}]>;
def uconst4 : PatLeaf<(imm), [{
	int val = (int)N->getSExtValue();
	return (val <= 15 && val >= 0);
}], uconst4_xform>;

def sconst5_xform : SDNodeXForm<imm, [{
	return CurDAG->getTargetConstant((int)N->getSExtValue(), MVT::i32);
}]>;
def sconst5 : PatLeaf<(imm), [{
	int val = (int)N->getSExtValue();
	return (val <= 15 && val >= -16);
}], sconst5_xform>;

def uconst5_xform : SDNodeXForm<imm, [{
	return CurDAG->getTargetConstant((int)N->getZExtValue(), MVT::i32);
}]>;
def uconst5 : PatLeaf<(imm), [{
	int val = (int)N->getZExtValue();
	return (val >= 0 && val < 32);
}], uconst5_xform>;

def uconst15_xform : SDNodeXForm<imm, [{
	return CurDAG->getTargetConstant((int)N->getZExtValue(), MVT::i32);
}]>;
def uconst15 : PatLeaf<(imm), [{
	int val = (int)N->getZExtValue();
	return (val < 0x7FF);
}], uconst15_xform>;

def sconst16_xform : SDNodeXForm<imm, [{
	return CurDAG->getTargetConstant((int)N->getZExtValue(), MVT::i32);
}]>;
def sconst16 : PatLeaf<(imm), [{
	int val = (int)N->getZExtValue();
	return (val >= -0x800 && val < 0x7FF);
}], sconst16_xform>;

def mvk_xform : SDNodeXForm<imm, [{
	return CurDAG->getTargetConstant((int)N->getSExtValue(), MVT::i32);
}]>;
def mvk_pred : PatLeaf<(imm), [{
	int val = (int)N->getSExtValue();
	return (val < 0x7FFF && val >= -0x8000);
}], mvk_xform>;

def mvk_all_pred : PatLeaf<(imm), [{
	return (N == N); // Avoid unused N warning
}], NOOP_SDNodeXForm>;

// ~

def set_lo : PatLeaf<(imm), [{
	unsigned int val = N->getZExtValue();
	return ((val & 0xFFFF) == val);
}]>;

def set_hi : PatLeaf<(imm), [{
	unsigned int val = (unsigned)N->getZExtValue();
	return ((val & 0xFFFF0000) == val);
}]>;

def pred : PredicateOperand<OtherVT, (ops timm, PredRegs),
			(ops (i32 -1), (i32 zero_reg))> {
	// Predicate of -1 indicates that this is always-execute
}

def nodefault_pred : PredicateOperand<OtherVT, (ops timm, PredRegs),
			(ops)>;

def nodefault_zflag : PredicateOperand<i32, (ops timm), (ops)>;
def nodefault_reg : PredicateOperand<i32, (ops PredRegs), (ops)>;

// NKIM, supply the root-node to the func, not sure about parent or root
// def predwrapper1 : ComplexPattern<i32, 1, "bounce_predicate", [], []>;
def predwrapper1 : ComplexPattern<i32, 1, "bounce_predicate", [], [SDNPWantRoot]>;

class inst<dag outops,
           dag inops,
           string asm_str,
           list<dag> pattern,
           bit side,
           InstUnit u>
: Instruction {

  // All insns are conditional unless stated otherwise
  let isPredicable = 1;
  let CodeSize = 4;

  let Namespace = "TMS320C64X";
  let OutOperandList = outops;

// NKIM, that causes tblgen crash for llvm higher than 2.7
//  let InOperandList = !con(ins, (ops pred:$s));
  let InOperandList = !con(inops, (ins pred:$s));
  let Itinerary = Default;

  let neverHasSideEffects = 1;
  let AsmString = asm_str;

  // Match nothing; set sched_pattern for a future tablegen backend
  // to play with. pseudo instrs over-ride this behavior.
  list<dag> sched_pattern = pattern;
  let Pattern = [];

  UnitSupport Supported = units_fixed;
  bits<3> DelaySlots = 0;
  bit MemAccess = 0;
  bits<2> MemShift = 0;
  bit MemLoadStore = 0;
  // default unit for 'mobile' (not units_fixed) instructions, otherwise
  // the single legal unit.
  InstUnit DefaultUnit = u;

  let TSFlags{0-3} = Supported.units; // unit support
  let TSFlags{4} = side; // cluster side (0: A, 1: B)
  let TSFlags{7-5} = DelaySlots; // (range: [0,5])
  let TSFlags{8} = MemAccess; // (instr is load/store)
  let TSFlags{10-9} = MemShift; // mem_shift_amt (XXX)
  let TSFlags{11} = MemLoadStore; // (0 for load, 1 for store)
  let TSFlags{13-12} = DefaultUnit.unit; // fixed/default unit
}

class pseudoinst<dag outops, dag inops, string asm, list<dag> pat>
  : inst<outops, inops, asm, pat, 0, unit_d>
{
  let InOperandList = inops;
  let Pattern = pat;

  let Itinerary = NoItinerary;

  // emit them (as asm comments) for the time being
  //let isCodeGenOnly = 1;
}

class nopred_inst<dag outops,
                  dag inops,
                  string mnemonic,
                  list<dag> pattern,
		  bit side,
                  InstUnit u> 
: inst<outops, inops, mnemonic, pattern, side, u>
{
//  let InOperandList = !con(ins, (ops nodefault_zflag:$a, nodefault_reg:$b));
  let InOperandList = !con(inops, (ins nodefault_zflag:$a, nodefault_reg:$b));
}

class memload<dag outs,
              dag ins,
              list<dag> pattern,
              bit side,
              InstUnit u>
: inst<outs, ins, "", pattern, side, u>
{
  let DelaySlots = 4;
  let hasDelaySlot = 1;

  let MemAccess = 1;
  let MemLoadStore = 0;

  let Itinerary = Load;
  let Supported = units_d;

}

class memstore<dag outs,
               dag ins,
               list<dag> pattern,
               bit side,
               InstUnit u>
: inst<outs, ins, "", pattern, side, u> 
{
  let MemAccess = 1;
  let MemLoadStore = 1;
  let Supported = units_d;
}

class pseudo_rr<string mnemonic,
                string sidespec,
                InstUnit u, 
                SDNode op,
                int swap>
: inst<(outs ARegs:$dst), (ins ARegs:$src1, ARegs:$src2), "",
       [(set ARegs:$dst, (op ARegs:$src1, ARegs:$src2))], 0, u>
{
  string comb_mnemonic = !strconcat(!strconcat(mnemonic, "\t"), sidespec);
  let AsmString = !if(swap,

  !strconcat(comb_mnemonic,"\t$src2,\t$src1,\t$dst"),
  !strconcat(comb_mnemonic, "\t$src1,\t$src2,\t$dst"));

  let Pattern = sched_pattern;
}

class pseudo_ri<string mnemonic, string sidespec, dag imm, InstUnit u,
                SDNode op, int swap>
: inst<(outs ARegs:$dst), (ins ARegs:$src1, i32imm:$imm), "",
        [(set ARegs:$dst, (op ARegs:$src1, imm))], 0, u>
{
  string comb_mnemonic = !strconcat(!strconcat(mnemonic, "\t"), sidespec);
  let AsmString = !if(swap,
  !strconcat(comb_mnemonic, "\t$imm,\t$src1,\t$dst"),
  !strconcat(comb_mnemonic, "\t$src1,\t$imm,\t$dst"));
  let Pattern = sched_pattern;
}

multiclass meminst_load_p<string mnemonic, PatFrag op> {

  def _load_p_addr : memload<(outs GPRegs:$dst), (ins mem_operand:$ptr),
                     [(set GPRegs:$dst, (op addr:$ptr))], 0, unit_d>
  {
    let Pattern = sched_pattern;
    let AsmString = !strconcat("ld",!strconcat(mnemonic, "\t\t$ptr,\t$dst"));
  }

  def _load_p_idx : memload<(outs GPRegs:$dst), (ins mem_operand:$ptr),
                    [(set GPRegs:$dst, (op idxaddr:$ptr))], 0, unit_d>
  {
    let Pattern = sched_pattern;
    let AsmString = !strconcat("ld",!strconcat(mnemonic, "\t\t$ptr,\t$dst"));
  }
}

multiclass meminst_store_p<string mnemonic, PatFrag op> {

  def _store_p_addr : memstore<(outs), (ins mem_operand:$ptr,GPRegs:$reg),
                      [(op GPRegs:$reg, addr:$ptr)], 0, unit_d>
  {
    let Pattern = sched_pattern;
    let AsmString = !strconcat("st",!strconcat(mnemonic, "\t\t$reg,\t$ptr"));
  }

  def _store_p_idx : memstore<(outs), (ins mem_operand:$ptr, GPRegs:$reg),
                     [(op GPRegs:$reg, idxaddr:$ptr)], 0, unit_d>
  {
    let Pattern = sched_pattern;
    let AsmString = !strconcat("st",!strconcat(mnemonic, "\t\t$reg,\t$ptr"));
  }
}

multiclass meminst_p<string mnemonic, PatFrag loadop, PatFrag storeop> :
  meminst_load_p<mnemonic, loadop>,
  meminst_store_p<mnemonic, storeop>;

//
// side-specific instructions
//

class InstructionFormat<dag OpTypes> : Operand<OtherVT> {
  let MIOperandInfo = OpTypes;
  let PrintMethod = "printFU";
}

def form : InstructionFormat<(ops timm)>;

class c64sideinst<dag outops, dag inops, string mnemonic, InstSide side>
: Instruction
{
  // All insns are conditional unless stated otherwise
  let isPredicable = 1;
  let CodeSize = 4;

  let Namespace = "C64X"; // XXX this seems to have no effect

  let OutOperandList = outops;
  let InOperandList = !con(inops, (ins pred:$s, form:$fu));

  let Itinerary = Default;
  let neverHasSideEffects = 1;

  //string sidestr = !strconcat("\t.", !if(side.intval, "1", "0"));
  let AsmString = !strconcat(mnemonic, "\t.$fu\t$src1,\t$src2,\t$dst");

  // side-specific instructions don't match
  let Pattern = [];

  UnitSupport Supported = units_any; // different to inst class
  bits<3> DelaySlots = 0;
  bit MemAccess = 0;
  bits<2> MemShift = 0;
  bit MemLoadStore = 0;
  InstUnit DefaultUnit = InstUnit<0>; // not used for this inst kind

  let TSFlags{0-3} = Supported.units; // unit support
  let TSFlags{4} = side.bitval; // cluster side (0: A, 1: B)
  let TSFlags{7-5} = DelaySlots; // (range: [0,5])
  let TSFlags{8} = MemAccess; // (instr is load/store)
  let TSFlags{10-9} = MemShift; // mem_shift_amt (XXX)
  let TSFlags{11} = MemLoadStore; // (0 for load, 1 for store)
  let TSFlags{13-12} = DefaultUnit.unit; // fixed/default unit
}

multiclass c64inst<dag indag, string mnemonic> {
        def _1 : c64sideinst<(outs ARegs:$dst), !con((ins ARegs:$src1), indag),
    mnemonic, side_a>;
        def _2 : c64sideinst<(outs BRegs:$dst), !con((ins BRegs:$src1), indag),
    mnemonic, side_b>;
}

// immediate version ($src2 is the immediate and and $src1 supports xpath)
multiclass c64iinst<dag indag, string mnemonic> {
        def _1 : c64sideinst<(outs ARegs:$dst), !con((ins GPRegs:$src1), indag),
    mnemonic, side_a>;
        def _2 : c64sideinst<(outs BRegs:$dst), !con((ins GPRegs:$src1), indag),
    mnemonic, side_b>;
}

// swapped version (src operands swapped for added confusion)
// used by instructions like shift: (TI's ASM reference) src2, src1, dst.
// LLVM has the src ops swapped and therefore $src2 must be side-fixed.
multiclass c64swinst<dag indag, string mnemonic> {
        def _1 : c64sideinst<(outs ARegs:$dst), !con(indag, (ins ARegs:$src2)),
    mnemonic, side_a>;
        def _2 : c64sideinst<(outs BRegs:$dst), !con(indag, (ins BRegs:$src2)),
    mnemonic, side_b>;
}

// side-specific load/store

def mem_op_a: Operand<i32> {
        let PrintMethod = "printMemOperand";
        let MIOperandInfo = (ops ARegs, ARegs);
}

def mem_op_b: Operand<i32> {
        let PrintMethod = "printMemOperand";
        let MIOperandInfo = (ops BRegs, BRegs);
}

class c64sideload<dag indag, dag outdag, string load, InstSide side> :
        c64sideinst<outdag, indag, "", side> {
  let DelaySlots = 4;
  let hasDelaySlot = 1;
  let MemAccess = 1;
  let MemLoadStore = 0;
  let mayLoad = 1;
  let Itinerary = Load;

  // restrict to D unit (note: load/store is not fixed, as we assign sides)
  let Supported = units_d;

  let AsmString = !strconcat("ld",!strconcat(load, "\t.$fu\t$ptr,\t$dst"));
}

class c64sidestore<dag indag, string store, InstSide side> :
        c64sideinst<(outs), !con(indag, (ins GPRegs:$reg)), "", side> {
  let MemAccess = 1;
  let MemLoadStore = 1;
  let mayStore = 1;

  // restrict to D unit (note: load/store is not fixed, as we assign sides)
  let Supported = units_d;

  let AsmString = !strconcat("st",!strconcat(store,
        "\t.$fu\t$reg,\t$ptr"));
}

multiclass c64load<string width> {
  def _load_1 : c64sideload<(ins mem_op_a:$ptr), (outs GPRegs:$dst), width, side_a>;
  def _load_2 : c64sideload<(ins mem_op_b:$ptr), (outs GPRegs:$dst), width, side_b>;
}

multiclass c64strictload<string width> {
  def _sload_1 : c64sideload<(ins mem_op_a:$ptr), (outs ARegs:$dst), width, side_a>;
  def _sload_2 : c64sideload<(ins mem_op_b:$ptr), (outs BRegs:$dst), width, side_b>;
}

multiclass c64store<string width> {
  def _store_1 : c64sidestore<(ins mem_op_a:$ptr), width, side_a>;
  def _store_2 : c64sidestore<(ins mem_op_b:$ptr), width, side_b>;
}