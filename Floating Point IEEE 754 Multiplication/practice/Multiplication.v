module Multiplication(input [32-1:0] a,
                        input [32-1:0] b,
                        output exception, 
                        output overflow,
                        output underflow,
                        output [32-1:0] res);

// data size= 32-bits
// sign size= 1-bits
// exponent size= 8-bits
// mantissa size= 23-bits
// sign: [31]
// exponent: [30:23]
// mantissa: [22:0]
parameter exponent_size=8;
parameter exponent_size_plus1=exponent_size+1;
parameter mantissa_size=23;
parameter mantissa_size_plus1=mantissa_size+1;
parameter mantissa_size_plus1_x2=mantissa_size_plus1*2;
parameter mantissa_size_plus1_x2_minus1=mantissa_size_plus1_x2-1;
parameter mantissa_size_plus1_x2_minus2=mantissa_size_plus1_x2-2;

wire sign;
wire round;
wire normalised;
wire zero;
wire [exponent_size_plus1-1:0] exponent;
// 9th bit for checking overflow(1_0000_0000) and underflow(1_1111_1111)
wire [exponent_size_plus1-1:0] sum_exponent;
// exponent before Bias(127)
wire [mantissa_size_plus1-1:0] op_a;
wire [mantissa_size_plus1-1:0] op_b;
wire [mantissa_size_plus1_x2-1:0] product;
wire [mantissa_size_plus1_x2-1:0] product_normalised;
wire [mantissa_size-1:0] product_mantissa;

assign sign = a[31]^b[31];  // XOR of 32nd bit
assign exception = (&a[30:23]) | (&b[30:23]);
// Exception sets to 1 when exponent of any a or b is 255 which is for alert.
// If exponent is 0, hidden bit is 0, not 1. -> Definition of FP32

assign op_a= (|a[30:23]) ? {1'b1, a[22:0]} : {1'b0, a[22:0]};
// op_a gets additional 1 for exponent of nonzero
assign op_b= (|b[30:23]) ? {1'b1, b[22:0]} : {1'b0, b[22:0]};
// op_b gets additional 1 for exponent of nonzero

assign product = op_a * op_b;
// Product of two significant figures
assign normalised = product[mantissa_size_plus1_x2_minus1] ? 1'b1 : 1'b0;
// See if it is normal number or not
assign product_normalised = normalised ? product : product << 1;
// Normalized value based on 48th bit
// If it is not normalised, we shift by 2 to the 1
assign round = |product_normalised[22:0];
// Last 22 bits are ORed for rounding off(BurRim or Cutoff) purpose
// 23 bit becomes into 1 bit

assign product_mantissa = 
    product_normalised[mantissa_size_plus1_x2_minus2:mantissa_size_plus1] + 
    {22'b0, (product_normalised[mantissa_size] & round)};

// Mantissa
assign zero = exception ? 
                1'b0 : 
                (product_mantissa == 23'd0) & !((|a[30:23]) & (|b[30:23]))? 
                // zero mantissa and zero exponent -> true zero
                1'b1 : 
                1'b0;
// Nested conditions for finding 0 expression of FP32
assign sum_exponent = a[30:23] + b[30:23];
// multiplication of 2^exponent -> sum of exponents
// verilator lint_off WIDTH
assign exponent = (|sum_exponent[exponent_size:exponent_size-1]) ? 
                    // sum_exponent[7] -> bias+1
                    sum_exponent - 8'd127 + normalised : 
                    8'd0;
// verilator lint_on WIDTH
// It was 'assign exponent = sum_exponent - 8'd127 + normalised;'
// exponent bias setting -> refer to definition of FP32
assign overflow = (
    (exponent[exponent_size] & !exponent[exponent_size-1]
    ) & !zero);
// If overall exponet is greater than 255 then Overflow
// Condition for overflow
assign underflow = (
    (exponent[exponent_size] & exponent[exponent_size-1]
    ) & !zero) ? 1'b1 : 1'b0;
// If sum of exponents is less than 255 then Underflow
// Condition for underflow
assign res = exception ? 32'd0 : 
                                zero ? {sign, 31'd0} : 
                                overflow ? {sign, 8'hFF, 23'd0} :
                                underflow ? {sign, 31'd0} : 
                                {
                                    sign, 
                                    exponent[exponent_size-1:0], 
                                    product_mantissa
                                };

endmodule


module multiplication_tb;

reg [32-1:0] a;
reg [32-1:0] b;
wire exception;
wire overflow;
wire underflow;
wire [32-1:0] res;

reg clk= 1'b1;

Multiplication dut(a,
                    b,
                    exception,
                    overflow,
                    underflow,
                    res);

always clk = #5 ~clk;
// Period: 5+5

// Code for watching waveform
initial
begin
    $dumpfile("Multiplication.vcd");  // any file name possible
    $dumpvars(0, multiplication_tb);  // instance name required
end

task iteration(input [32-1:0] op_a,
                input [32-1:0] op_b,
                input Expected_Exception,
                input Expected_Overflow,
                input Expected_Underflow,
                input [32-1:0] Expected_result,
                input integer linenum);

begin
    @(negedge clk)
    begin
        a = op_a;
        b = op_b;
    end

    @(posedge clk)
    begin
        if((Expected_result == res) && 
            (Expected_Exception == exception) && 
            (Expected_Overflow == overflow) && 
            (Expected_Underflow == underflow))
            $display("Success : %d", linenum);

        else
        begin
            $display("Failed : ",
                        "Expected_result = %h, Result = %h, \n ",
                        Expected_result,
                        res,
                        "Expected_Exception = %d, Exception = %d, \n ",
                        Expected_Exception,
                        exception,
                        "Expected_Overflow = %d, Overflow = %d, \n ",
                        Expected_Overflow,
                        overflow,
                        "Expected_Underflow = %d, Underflow = %d - %d \n ", 
                        Expected_Underflow,
                        underflow,
                        linenum);
        end
    end
end
endtask



initial
begin
    iteration(32'h0200_0000, 
                32'h0200_0000,
                1'b0,
                1'b0,
                1'b0,
                32'h0000_0000,
                `__LINE__);

    iteration(32'h4234_851F,
                32'h427C_851F,
                1'b0,
                1'b0,
                1'b0,
                32'h4532_10E9,
                `__LINE__);
    // 45.13 * 63.13 = 2849.0569

    iteration(32'h4049_999A,
                32'hC166_3D71,
                1'b0,
                1'b0,
                1'b0,
                32'hC235_5062,
                `__LINE__);
    // 3.15 * -14.39 = -45.3285

    iteration(32'hC152_6666,
                32'hC240_A3D7,
                1'b0,
                1'b0,
                1'b0,
                32'h441E_5375,
                `__LINE__);
    // -13.15 * -48.16 = 633.304

    iteration(32'h4580_0000,
                32'h4580_0000,
                1'b0,
                1'b0,
                1'b0,
                32'h4B80_0000,
                `__LINE__);
    // 4096 * 4096 = 16777216

    iteration(32'h3ACA_62C1,
                32'h3ACA_62C1,
                1'b0,
                1'b0,
                1'b0,
                32'h361F_FFE7,
                `__LINE__);
    // 0.00154408081 * 0.00154408081 = 0.00000238418

    iteration(32'h0000_0000,
                32'h0000_0000,
                1'b0,
                1'b0,
                1'b0,
                32'h0000_0000,
                `__LINE__);
    // 0 * 0 = 0

    iteration(32'hC152_6666,
                32'h0000_0000,
                1'b0,
                1'b0,
                1'b0,
                32'h8000_0000,
                `__LINE__);
    // -13.15 * 0 = 0

    iteration(32'h7F80_0000,
                32'h7F80_0000,
                1'b1,
                1'b1,
                1'b0,
                32'h0000_0000,
                `__LINE__);

    // $stop;

    $finish;

end

endmodule



