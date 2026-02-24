extern "C" __global__ void batch_encode(const unsigned char *input, unsigned int *output, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) output[i] = (unsigned int)input[i];
}
