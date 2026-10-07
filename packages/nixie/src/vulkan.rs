//! An off-screen Vulkan pass: one compute dispatch, one picture, no window.
//!
//! There is no surface, no swapchain, no compositor and no monitor anywhere in
//! here — the tube is rendered into an image the process owns and read straight
//! back. That is what makes a configuration cheap enough to sweep: a frame is a
//! dispatch, not a session.

use anyhow::{anyhow, Context, Result};
use ash::vk;
use std::ffi::CStr;

pub struct Frame {
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
}

struct Gpu {
    _entry: ash::Entry,
    instance: ash::Instance,
    device: ash::Device,
    queue: vk::Queue,
    queue_family: u32,
    memory_properties: vk::PhysicalDeviceMemoryProperties,
}

impl Gpu {
    fn new() -> Result<Self> {
        unsafe {
            let entry = ash::Entry::load().context("loading libvulkan")?;
            let app = vk::ApplicationInfo::default().api_version(vk::make_api_version(0, 1, 1, 0));
            let info = vk::InstanceCreateInfo::default().application_info(&app);
            let instance = entry.create_instance(&info, None)?;
            let devices = instance.enumerate_physical_devices()?;
            let physical = *devices.first().ok_or_else(|| anyhow!("no Vulkan device"))?;
            let props = instance.get_physical_device_properties(physical);
            let name = CStr::from_ptr(props.device_name.as_ptr()).to_string_lossy();
            let families = instance.get_physical_device_queue_family_properties(physical);
            let family = families
                .iter()
                .position(|f| f.queue_flags.contains(vk::QueueFlags::COMPUTE))
                .ok_or_else(|| anyhow!("{name} has no compute queue"))?
                as u32;
            let priorities = [1.0f32];
            let queue_info = [vk::DeviceQueueCreateInfo::default()
                .queue_family_index(family)
                .queue_priorities(&priorities)];
            let device_info = vk::DeviceCreateInfo::default().queue_create_infos(&queue_info);
            let device = instance.create_device(physical, &device_info, None)?;
            let queue = device.get_device_queue(family, 0);
            let memory_properties = instance.get_physical_device_memory_properties(physical);
            eprintln!("nixie: {name}, compute queue family {family}");
            Ok(Gpu {
                _entry: entry,
                instance,
                device,
                queue,
                queue_family: family,
                memory_properties,
            })
        }
    }

    fn memory_type(&self, bits: u32, want: vk::MemoryPropertyFlags) -> Result<u32> {
        for i in 0..self.memory_properties.memory_type_count {
            let has = bits & (1 << i) != 0;
            let ok = self.memory_properties.memory_types[i as usize]
                .property_flags
                .contains(want);
            if has && ok {
                return Ok(i);
            }
        }
        Err(anyhow!("no memory type for {want:?}"))
    }
}

/// Render one tube into `width x height` device pixels.
pub fn render(
    shader_spv: &std::path::Path,
    uniforms: &Uniforms,
    wallpaper: &image::RgbaImage,
    width: u32,
    height: u32,
) -> Result<Frame> {
    let gpu = Gpu::new()?;
    unsafe { dispatch(&gpu, shader_spv, uniforms, wallpaper, width, height) }
}

use crate::uniforms::Uniforms;

unsafe fn dispatch(
    gpu: &Gpu,
    shader_spv: &std::path::Path,
    uniforms: &Uniforms,
    wallpaper: &image::RgbaImage,
    width: u32,
    height: u32,
) -> Result<Frame> {
    let device = &gpu.device;

    // the output image: storage, so a compute shader can write it, and
    // transfer-src, so the host can read it back
    let out_image = device.create_image(
        &vk::ImageCreateInfo::default()
            .image_type(vk::ImageType::TYPE_2D)
            .format(vk::Format::R8G8B8A8_UNORM)
            .extent(vk::Extent3D {
                width,
                height,
                depth: 1,
            })
            .mip_levels(1)
            .array_layers(1)
            .samples(vk::SampleCountFlags::TYPE_1)
            .tiling(vk::ImageTiling::OPTIMAL)
            .usage(vk::ImageUsageFlags::STORAGE | vk::ImageUsageFlags::TRANSFER_SRC)
            .sharing_mode(vk::SharingMode::EXCLUSIVE)
            .initial_layout(vk::ImageLayout::UNDEFINED),
        None,
    )?;
    let out_req = device.get_image_memory_requirements(out_image);
    let out_mem = device.allocate_memory(
        &vk::MemoryAllocateInfo::default()
            .allocation_size(out_req.size)
            .memory_type_index(gpu.memory_type(
                out_req.memory_type_bits,
                vk::MemoryPropertyFlags::DEVICE_LOCAL,
            )?),
        None,
    )?;
    device.bind_image_memory(out_image, out_mem, 0)?;
    let out_view = device.create_image_view(
        &vk::ImageViewCreateInfo::default()
            .image(out_image)
            .view_type(vk::ImageViewType::TYPE_2D)
            .format(vk::Format::R8G8B8A8_UNORM)
            .subresource_range(vk::ImageSubresourceRange {
                aspect_mask: vk::ImageAspectFlags::COLOR,
                level_count: 1,
                layer_count: 1,
                ..Default::default()
            }),
        None,
    )?;

    // the wallpaper the glass bends: a sampled image, filled from the host
    let (ww, wh) = wallpaper.dimensions();
    let wall_image = device.create_image(
        &vk::ImageCreateInfo::default()
            .image_type(vk::ImageType::TYPE_2D)
            .format(vk::Format::R8G8B8A8_UNORM)
            .extent(vk::Extent3D {
                width: ww,
                height: wh,
                depth: 1,
            })
            .mip_levels(1)
            .array_layers(1)
            .samples(vk::SampleCountFlags::TYPE_1)
            .tiling(vk::ImageTiling::OPTIMAL)
            .usage(vk::ImageUsageFlags::SAMPLED | vk::ImageUsageFlags::TRANSFER_DST)
            .sharing_mode(vk::SharingMode::EXCLUSIVE)
            .initial_layout(vk::ImageLayout::UNDEFINED),
        None,
    )?;
    let wall_req = device.get_image_memory_requirements(wall_image);
    let wall_mem = device.allocate_memory(
        &vk::MemoryAllocateInfo::default()
            .allocation_size(wall_req.size)
            .memory_type_index(gpu.memory_type(
                wall_req.memory_type_bits,
                vk::MemoryPropertyFlags::DEVICE_LOCAL,
            )?),
        None,
    )?;
    device.bind_image_memory(wall_image, wall_mem, 0)?;

    // the staging buffer with the wallpaper's pixels
    let pixels = wallpaper.as_raw();
    let staging = device.create_buffer(
        &vk::BufferCreateInfo::default()
            .size(pixels.len() as u64)
            .usage(vk::BufferUsageFlags::TRANSFER_SRC)
            .sharing_mode(vk::SharingMode::EXCLUSIVE),
        None,
    )?;
    let staging_req = device.get_buffer_memory_requirements(staging);
    let staging_mem = device.allocate_memory(
        &vk::MemoryAllocateInfo::default()
            .allocation_size(staging_req.size)
            .memory_type_index(gpu.memory_type(
                staging_req.memory_type_bits,
                vk::MemoryPropertyFlags::HOST_VISIBLE | vk::MemoryPropertyFlags::HOST_COHERENT,
            )?),
        None,
    )?;
    device.bind_buffer_memory(staging, staging_mem, 0)?;
    let ptr = device.map_memory(
        staging_mem,
        0,
        staging_req.size,
        vk::MemoryMapFlags::empty(),
    )?;
    std::ptr::copy_nonoverlapping(pixels.as_ptr(), ptr as *mut u8, pixels.len());
    device.unmap_memory(staging_mem);

    // the uniforms
    let ub_size = std::mem::size_of::<Uniforms>() as u64;
    let ub = device.create_buffer(
        &vk::BufferCreateInfo::default()
            .size(ub_size)
            .usage(vk::BufferUsageFlags::UNIFORM_BUFFER)
            .sharing_mode(vk::SharingMode::EXCLUSIVE),
        None,
    )?;
    let ub_req = device.get_buffer_memory_requirements(ub);
    let ub_mem = device.allocate_memory(
        &vk::MemoryAllocateInfo::default()
            .allocation_size(ub_req.size)
            .memory_type_index(gpu.memory_type(
                ub_req.memory_type_bits,
                vk::MemoryPropertyFlags::HOST_VISIBLE | vk::MemoryPropertyFlags::HOST_COHERENT,
            )?),
        None,
    )?;
    device.bind_buffer_memory(ub, ub_mem, 0)?;
    let ptr = device.map_memory(ub_mem, 0, ub_req.size, vk::MemoryMapFlags::empty())?;
    std::ptr::copy_nonoverlapping(
        uniforms as *const Uniforms as *const u8,
        ptr as *mut u8,
        std::mem::size_of::<Uniforms>(),
    );
    device.unmap_memory(ub_mem);

    // the picture the tool wrote out of the frame
    let readback = device.create_buffer(
        &vk::BufferCreateInfo::default()
            .size((width * height * 4) as u64)
            .usage(vk::BufferUsageFlags::TRANSFER_DST)
            .sharing_mode(vk::SharingMode::EXCLUSIVE),
        None,
    )?;
    let rb_req = device.get_buffer_memory_requirements(readback);
    let rb_mem = device.allocate_memory(
        &vk::MemoryAllocateInfo::default()
            .allocation_size(rb_req.size)
            .memory_type_index(gpu.memory_type(
                rb_req.memory_type_bits,
                vk::MemoryPropertyFlags::HOST_VISIBLE | vk::MemoryPropertyFlags::HOST_COHERENT,
            )?),
        None,
    )?;
    device.bind_buffer_memory(readback, rb_mem, 0)?;

    // the descriptors: the uniforms, the wallpaper, the output
    let bindings = [
        vk::DescriptorSetLayoutBinding::default()
            .binding(0)
            .descriptor_type(vk::DescriptorType::UNIFORM_BUFFER)
            .descriptor_count(1)
            .stage_flags(vk::ShaderStageFlags::COMPUTE),
        vk::DescriptorSetLayoutBinding::default()
            .binding(1)
            .descriptor_type(vk::DescriptorType::COMBINED_IMAGE_SAMPLER)
            .descriptor_count(1)
            .stage_flags(vk::ShaderStageFlags::COMPUTE),
        vk::DescriptorSetLayoutBinding::default()
            .binding(2)
            .descriptor_type(vk::DescriptorType::STORAGE_IMAGE)
            .descriptor_count(1)
            .stage_flags(vk::ShaderStageFlags::COMPUTE),
    ];
    let set_layout = device.create_descriptor_set_layout(
        &vk::DescriptorSetLayoutCreateInfo::default().bindings(&bindings),
        None,
    )?;
    let pool = device.create_descriptor_pool(
        &vk::DescriptorPoolCreateInfo::default()
            .max_sets(1)
            .pool_sizes(&[
                vk::DescriptorPoolSize::default()
                    .ty(vk::DescriptorType::UNIFORM_BUFFER)
                    .descriptor_count(1),
                vk::DescriptorPoolSize::default()
                    .ty(vk::DescriptorType::COMBINED_IMAGE_SAMPLER)
                    .descriptor_count(1),
                vk::DescriptorPoolSize::default()
                    .ty(vk::DescriptorType::STORAGE_IMAGE)
                    .descriptor_count(1),
            ]),
        None,
    )?;
    let layouts = [set_layout];
    let set = device.allocate_descriptor_sets(
        &vk::DescriptorSetAllocateInfo::default()
            .descriptor_pool(pool)
            .set_layouts(&layouts),
    )?[0];

    let sampler = device.create_sampler(
        &vk::SamplerCreateInfo::default()
            .mag_filter(vk::Filter::LINEAR)
            .min_filter(vk::Filter::LINEAR)
            .address_mode_u(vk::SamplerAddressMode::CLAMP_TO_EDGE)
            .address_mode_v(vk::SamplerAddressMode::CLAMP_TO_EDGE)
            .address_mode_w(vk::SamplerAddressMode::CLAMP_TO_EDGE),
        None,
    )?;

    let ub_info = [vk::DescriptorBufferInfo::default()
        .buffer(ub)
        .offset(0)
        .range(ub_size)];
    let wall_info = [vk::DescriptorImageInfo::default()
        .image_layout(vk::ImageLayout::GENERAL)
        .image_view(
            device.create_image_view(
                &vk::ImageViewCreateInfo::default()
                    .image(wall_image)
                    .view_type(vk::ImageViewType::TYPE_2D)
                    .format(vk::Format::R8G8B8A8_UNORM)
                    .subresource_range(vk::ImageSubresourceRange {
                        aspect_mask: vk::ImageAspectFlags::COLOR,
                        level_count: 1,
                        layer_count: 1,
                        ..Default::default()
                    }),
                None,
            )?,
        )
        .sampler(sampler)];
    let out_info = [vk::DescriptorImageInfo::default()
        .image_layout(vk::ImageLayout::GENERAL)
        .image_view(out_view)];
    let writes = [
        vk::WriteDescriptorSet::default()
            .dst_set(set)
            .dst_binding(0)
            .descriptor_type(vk::DescriptorType::UNIFORM_BUFFER)
            .buffer_info(&ub_info),
        vk::WriteDescriptorSet::default()
            .dst_set(set)
            .dst_binding(1)
            .descriptor_type(vk::DescriptorType::COMBINED_IMAGE_SAMPLER)
            .image_info(&wall_info),
        vk::WriteDescriptorSet::default()
            .dst_set(set)
            .dst_binding(2)
            .descriptor_type(vk::DescriptorType::STORAGE_IMAGE)
            .image_info(&out_info),
    ];
    device.update_descriptor_sets(&writes, &[]);

    // the pipeline
    let bytes = std::fs::read(shader_spv)?;
    let code: Vec<u32> = bytes
        .chunks_exact(4)
        .map(|w| u32::from_le_bytes([w[0], w[1], w[2], w[3]]))
        .collect();
    let module =
        device.create_shader_module(&vk::ShaderModuleCreateInfo::default().code(&code), None)?;
    let stage = vk::PipelineShaderStageCreateInfo::default()
        .stage(vk::ShaderStageFlags::COMPUTE)
        .module(module)
        .name(CStr::from_bytes_with_nul(b"main\0")?);
    let pipeline_layout = device.create_pipeline_layout(
        &vk::PipelineLayoutCreateInfo::default().set_layouts(&layouts),
        None,
    )?;
    let pipelines = device
        .create_compute_pipelines(
            vk::PipelineCache::null(),
            &[vk::ComputePipelineCreateInfo::default()
                .stage(stage)
                .layout(pipeline_layout)],
            None,
        )
        .map_err(|(_, e)| e)?;
    let pipeline = pipelines[0];

    // one command buffer: upload, run, read back
    let pool = device.create_command_pool(
        &vk::CommandPoolCreateInfo::default().queue_family_index(gpu.queue_family),
        None,
    )?;
    let cmd = device.allocate_command_buffers(
        &vk::CommandBufferAllocateInfo::default()
            .command_pool(pool)
            .level(vk::CommandBufferLevel::PRIMARY)
            .command_buffer_count(1),
    )?[0];
    device.begin_command_buffer(
        cmd,
        &vk::CommandBufferBeginInfo::default().flags(vk::CommandBufferUsageFlags::ONE_TIME_SUBMIT),
    )?;

    let to_general = vk::ImageMemoryBarrier::default()
        .old_layout(vk::ImageLayout::UNDEFINED)
        .new_layout(vk::ImageLayout::GENERAL)
        .src_access_mask(vk::AccessFlags::empty())
        .dst_access_mask(vk::AccessFlags::TRANSFER_WRITE | vk::AccessFlags::SHADER_WRITE)
        .image(out_image)
        .subresource_range(vk::ImageSubresourceRange {
            aspect_mask: vk::ImageAspectFlags::COLOR,
            level_count: 1,
            layer_count: 1,
            ..Default::default()
        });
    let wall_to_general = vk::ImageMemoryBarrier::default()
        .old_layout(vk::ImageLayout::UNDEFINED)
        .new_layout(vk::ImageLayout::GENERAL)
        .src_access_mask(vk::AccessFlags::empty())
        .dst_access_mask(vk::AccessFlags::TRANSFER_WRITE)
        .image(wall_image)
        .subresource_range(vk::ImageSubresourceRange {
            aspect_mask: vk::ImageAspectFlags::COLOR,
            level_count: 1,
            layer_count: 1,
            ..Default::default()
        });
    device.cmd_pipeline_barrier(
        cmd,
        vk::PipelineStageFlags::TOP_OF_PIPE,
        vk::PipelineStageFlags::TRANSFER | vk::PipelineStageFlags::COMPUTE_SHADER,
        vk::DependencyFlags::empty(),
        &[],
        &[],
        &[to_general, wall_to_general],
    );

    device.cmd_copy_buffer_to_image(
        cmd,
        staging,
        wall_image,
        vk::ImageLayout::GENERAL,
        &[vk::BufferImageCopy::default()
            .image_subresource(vk::ImageSubresourceLayers {
                aspect_mask: vk::ImageAspectFlags::COLOR,
                layer_count: 1,
                ..Default::default()
            })
            .image_extent(vk::Extent3D {
                width: ww,
                height: wh,
                depth: 1,
            })],
    );
    device.cmd_pipeline_barrier(
        cmd,
        vk::PipelineStageFlags::TRANSFER,
        vk::PipelineStageFlags::COMPUTE_SHADER,
        vk::DependencyFlags::empty(),
        &[],
        &[],
        &[],
    );

    device.cmd_bind_pipeline(cmd, vk::PipelineBindPoint::COMPUTE, pipeline);
    device.cmd_bind_descriptor_sets(
        cmd,
        vk::PipelineBindPoint::COMPUTE,
        pipeline_layout,
        0,
        &[set],
        &[],
    );
    device.cmd_dispatch(cmd, width.div_ceil(8), height.div_ceil(8), 1);

    let out_to_transfer = vk::ImageMemoryBarrier::default()
        .old_layout(vk::ImageLayout::GENERAL)
        .new_layout(vk::ImageLayout::TRANSFER_SRC_OPTIMAL)
        .src_access_mask(vk::AccessFlags::SHADER_WRITE)
        .dst_access_mask(vk::AccessFlags::TRANSFER_READ)
        .image(out_image)
        .subresource_range(vk::ImageSubresourceRange {
            aspect_mask: vk::ImageAspectFlags::COLOR,
            level_count: 1,
            layer_count: 1,
            ..Default::default()
        });
    device.cmd_pipeline_barrier(
        cmd,
        vk::PipelineStageFlags::COMPUTE_SHADER,
        vk::PipelineStageFlags::TRANSFER,
        vk::DependencyFlags::empty(),
        &[],
        &[],
        &[out_to_transfer],
    );
    device.cmd_copy_image_to_buffer(
        cmd,
        out_image,
        vk::ImageLayout::TRANSFER_SRC_OPTIMAL,
        readback,
        &[vk::BufferImageCopy::default()
            .image_subresource(vk::ImageSubresourceLayers {
                aspect_mask: vk::ImageAspectFlags::COLOR,
                layer_count: 1,
                ..Default::default()
            })
            .image_extent(vk::Extent3D {
                width,
                height,
                depth: 1,
            })],
    );
    device.end_command_buffer(cmd)?;

    let cmds = [cmd];
    let submit = vk::SubmitInfo::default().command_buffers(&cmds);
    device.queue_submit(gpu.queue, &[submit], vk::Fence::null())?;
    device.queue_wait_idle(gpu.queue)?;

    let ptr = device.map_memory(rb_mem, 0, rb_req.size, vk::MemoryMapFlags::empty())?;
    let mut rgba = vec![0u8; (width * height * 4) as usize];
    std::ptr::copy_nonoverlapping(ptr as *const u8, rgba.as_mut_ptr(), rgba.len());
    device.unmap_memory(rb_mem);

    Ok(Frame {
        width,
        height,
        rgba,
    })
}
