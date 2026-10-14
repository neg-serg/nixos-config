//! An off-screen Vulkan pass: one compute dispatch, one picture, no window.
//!
//! There is no surface, no swapchain, no compositor and no monitor anywhere in
//! here — the tube is rendered into an image the process owns and read straight
//! back. That is what makes a configuration cheap enough to sweep: a frame is a
//! dispatch, not a session.
//!
//! Every Vulkan object is owned by `Pass`, whose `Drop` waits the queue idle and
//! destroys what it created, in reverse order — including on every `?` error
//! path. The instance and the device live in `Gpu`, created once per command
//! invocation, so a sweep no longer builds eleven devices it never frees.

use anyhow::{anyhow, Context, Result};
use ash::vk;
use std::ffi::CStr;
use std::path::Path;

pub struct Frame {
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
}

/// The process's logical device. One per command invocation, dropped with it.
pub struct Gpu {
    _entry: ash::Entry,
    instance: ash::Instance,
    device: ash::Device,
    queue: vk::Queue,
    queue_family: u32,
    memory_properties: vk::PhysicalDeviceMemoryProperties,
    description: String,
}

impl Gpu {
    /// `preferred` is a `--device N` index; without it the best compute device
    /// wins (discrete > integrated > virtual > CPU), and the choice is printed,
    /// because two runs must not silently measure two different devices.
    pub fn new(preferred: Option<u32>) -> Result<Self> {
        unsafe {
            let entry = ash::Entry::load()
                .context("loading libvulkan (is a Vulkan loader/driver installed?)")?;
            let app = vk::ApplicationInfo::default().api_version(vk::make_api_version(0, 1, 1, 0));
            let info = vk::InstanceCreateInfo::default().application_info(&app);
            let instance = entry
                .create_instance(&info, None)
                .context("creating a Vulkan instance")?;
            let (physical, family, description) = match pick_device(&instance, preferred) {
                Ok(picked) => picked,
                Err(e) => {
                    instance.destroy_instance(None);
                    return Err(e);
                }
            };
            let priorities = [1.0f32];
            let queue_info = [vk::DeviceQueueCreateInfo::default()
                .queue_family_index(family)
                .queue_priorities(&priorities)];
            let device_info = vk::DeviceCreateInfo::default().queue_create_infos(&queue_info);
            let device = match instance.create_device(physical, &device_info, None) {
                Ok(device) => device,
                Err(e) => {
                    instance.destroy_instance(None);
                    return Err(e).context("creating a Vulkan device");
                }
            };
            let queue = device.get_device_queue(family, 0);
            let memory_properties = instance.get_physical_device_memory_properties(physical);
            eprintln!("nixie: {description}, compute queue family {family}");
            Ok(Gpu {
                _entry: entry,
                instance,
                device,
                queue,
                queue_family: family,
                memory_properties,
                description,
            })
        }
    }

    pub fn description(&self) -> &str {
        &self.description
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

impl Drop for Gpu {
    fn drop(&mut self) {
        unsafe {
            let _ = self.device.device_wait_idle();
            self.device.destroy_device(None);
            self.instance.destroy_instance(None);
        }
    }
}

/// Pick a physical device that can compute, preferring real GPUs over llvmpipe.
unsafe fn pick_device(
    instance: &ash::Instance,
    preferred: Option<u32>,
) -> Result<(vk::PhysicalDevice, u32, String)> {
    let devices = instance
        .enumerate_physical_devices()
        .context("enumerating Vulkan devices")?;
    if devices.is_empty() {
        return Err(anyhow!(
            "no Vulkan device: no driver/ICD was found (set VK_ICD_FILENAMES or install one)"
        ));
    }
    let compute_family = |physical: vk::PhysicalDevice| -> Option<u32> {
        instance
            .get_physical_device_queue_family_properties(physical)
            .iter()
            .position(|f| f.queue_flags.contains(vk::QueueFlags::COMPUTE))
            .map(|i| i as u32)
    };
    let name_of = |physical: vk::PhysicalDevice| -> String {
        let props = instance.get_physical_device_properties(physical);
        CStr::from_ptr(props.device_name.as_ptr())
            .to_string_lossy()
            .into_owned()
    };
    if let Some(index) = preferred {
        let physical = *devices.get(index as usize).ok_or_else(|| {
            anyhow!(
                "--device {index}: this host has {} Vulkan device(s)",
                devices.len()
            )
        })?;
        let family = compute_family(physical).ok_or_else(|| {
            anyhow!(
                "--device {index} ({}) has no compute queue",
                name_of(physical)
            )
        })?;
        let ty = type_name(
            instance
                .get_physical_device_properties(physical)
                .device_type,
        );
        return Ok((physical, family, format!("{} ({ty})", name_of(physical))));
    }
    let mut best: Option<(u32, vk::PhysicalDevice, u32, String)> = None;
    for physical in devices {
        let Some(family) = compute_family(physical) else {
            continue;
        };
        let props = instance.get_physical_device_properties(physical);
        let score = match props.device_type {
            vk::PhysicalDeviceType::DISCRETE_GPU => 4,
            vk::PhysicalDeviceType::INTEGRATED_GPU => 3,
            vk::PhysicalDeviceType::VIRTUAL_GPU => 2,
            vk::PhysicalDeviceType::CPU => 1,
            _ => 0,
        };
        let better = match best.as_ref() {
            Some((best_score, ..)) => score > *best_score,
            None => true,
        };
        if better {
            let name = name_of(physical);
            best = Some((
                score,
                physical,
                family,
                format!("{name} ({})", type_name(props.device_type)),
            ));
        }
    }
    let (_, physical, family, description) = best.ok_or_else(|| {
        anyhow!(
            "no Vulkan device has a compute queue ({} device(s) enumerated)",
            instance
                .enumerate_physical_devices()
                .map(|d| d.len())
                .unwrap_or(0)
        )
    })?;
    Ok((physical, family, description))
}

fn type_name(t: vk::PhysicalDeviceType) -> &'static str {
    match t {
        vk::PhysicalDeviceType::DISCRETE_GPU => "discrete GPU",
        vk::PhysicalDeviceType::INTEGRATED_GPU => "integrated GPU",
        vk::PhysicalDeviceType::VIRTUAL_GPU => "virtual GPU",
        vk::PhysicalDeviceType::CPU => "CPU",
        _ => "other",
    }
}

/// Everything one dispatch creates, destroyed by `Drop` in reverse order.
struct Pass<'a> {
    dev: &'a ash::Device,
    queue: vk::Queue,
    out_image: Option<vk::Image>,
    out_mem: Option<vk::DeviceMemory>,
    out_view: Option<vk::ImageView>,
    wall_image: Option<vk::Image>,
    wall_mem: Option<vk::DeviceMemory>,
    wall_view: Option<vk::ImageView>,
    staging: Option<vk::Buffer>,
    staging_mem: Option<vk::DeviceMemory>,
    ub: Option<vk::Buffer>,
    ub_mem: Option<vk::DeviceMemory>,
    readback: Option<vk::Buffer>,
    readback_mem: Option<vk::DeviceMemory>,
    set_layout: Option<vk::DescriptorSetLayout>,
    pool: Option<vk::DescriptorPool>,
    sampler: Option<vk::Sampler>,
    module: Option<vk::ShaderModule>,
    pipeline_layout: Option<vk::PipelineLayout>,
    pipeline: Option<vk::Pipeline>,
    command_pool: Option<vk::CommandPool>,
}

impl<'a> Pass<'a> {
    fn new(dev: &'a ash::Device, queue: vk::Queue) -> Self {
        Self {
            dev,
            queue,
            out_image: None,
            out_mem: None,
            out_view: None,
            wall_image: None,
            wall_mem: None,
            wall_view: None,
            staging: None,
            staging_mem: None,
            ub: None,
            ub_mem: None,
            readback: None,
            readback_mem: None,
            set_layout: None,
            pool: None,
            sampler: None,
            module: None,
            pipeline_layout: None,
            pipeline: None,
            command_pool: None,
        }
    }
}

impl Drop for Pass<'_> {
    fn drop(&mut self) {
        unsafe {
            let dev = self.dev;
            // a submit may still be in flight on an error path
            let _ = dev.queue_wait_idle(self.queue);
            if let Some(p) = self.pipeline.take() {
                dev.destroy_pipeline(p, None);
            }
            if let Some(l) = self.pipeline_layout.take() {
                dev.destroy_pipeline_layout(l, None);
            }
            if let Some(p) = self.pool.take() {
                dev.destroy_descriptor_pool(p, None);
            }
            if let Some(l) = self.set_layout.take() {
                dev.destroy_descriptor_set_layout(l, None);
            }
            if let Some(s) = self.sampler.take() {
                dev.destroy_sampler(s, None);
            }
            if let Some(m) = self.module.take() {
                dev.destroy_shader_module(m, None);
            }
            if let Some(p) = self.command_pool.take() {
                dev.destroy_command_pool(p, None);
            }
            if let Some(b) = self.staging.take() {
                dev.destroy_buffer(b, None);
            }
            if let Some(m) = self.staging_mem.take() {
                dev.free_memory(m, None);
            }
            if let Some(b) = self.ub.take() {
                dev.destroy_buffer(b, None);
            }
            if let Some(m) = self.ub_mem.take() {
                dev.free_memory(m, None);
            }
            if let Some(b) = self.readback.take() {
                dev.destroy_buffer(b, None);
            }
            if let Some(m) = self.readback_mem.take() {
                dev.free_memory(m, None);
            }
            if let Some(v) = self.wall_view.take() {
                dev.destroy_image_view(v, None);
            }
            if let Some(i) = self.wall_image.take() {
                dev.destroy_image(i, None);
            }
            if let Some(m) = self.wall_mem.take() {
                dev.free_memory(m, None);
            }
            if let Some(v) = self.out_view.take() {
                dev.destroy_image_view(v, None);
            }
            if let Some(i) = self.out_image.take() {
                dev.destroy_image(i, None);
            }
            if let Some(m) = self.out_mem.take() {
                dev.free_memory(m, None);
            }
        }
    }
}

/// Render one tube into `width x height` device pixels on an existing device.
/// `ubo` is the packed std140 uniform block produced by `Uniforms::pack`.
pub fn render(
    gpu: &Gpu,
    shader_spv: &Path,
    ubo: &[u8],
    wallpaper: &image::RgbaImage,
    width: u32,
    height: u32,
) -> Result<Frame> {
    unsafe { dispatch(gpu, shader_spv, ubo, wallpaper, width, height) }
}

unsafe fn dispatch(
    gpu: &Gpu,
    shader_spv: &Path,
    ubo: &[u8],
    wallpaper: &image::RgbaImage,
    width: u32,
    height: u32,
) -> Result<Frame> {
    let dev = &gpu.device;
    let mut pass = Pass::new(dev, gpu.queue);

    // the output image: storage, so a compute shader can write it, and
    // transfer-src, so the host can read it back
    let out_image = dev
        .create_image(
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
        )
        .with_context(|| format!("creating a {width}x{height} output image"))?;
    pass.out_image = Some(out_image);
    let out_req = dev.get_image_memory_requirements(out_image);
    let out_mem = dev.allocate_memory(
        &vk::MemoryAllocateInfo::default()
            .allocation_size(out_req.size)
            .memory_type_index(gpu.memory_type(
                out_req.memory_type_bits,
                vk::MemoryPropertyFlags::DEVICE_LOCAL,
            )?),
        None,
    )?;
    pass.out_mem = Some(out_mem);
    dev.bind_image_memory(out_image, out_mem, 0)?;
    let out_view = dev.create_image_view(
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
    pass.out_view = Some(out_view);

    // the wallpaper the glass bends: a sampled image, filled from the host
    let (ww, wh) = wallpaper.dimensions();
    let wall_image = dev
        .create_image(
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
        )
        .with_context(|| format!("creating a {ww}x{wh} wallpaper image"))?;
    pass.wall_image = Some(wall_image);
    let wall_req = dev.get_image_memory_requirements(wall_image);
    let wall_mem = dev.allocate_memory(
        &vk::MemoryAllocateInfo::default()
            .allocation_size(wall_req.size)
            .memory_type_index(gpu.memory_type(
                wall_req.memory_type_bits,
                vk::MemoryPropertyFlags::DEVICE_LOCAL,
            )?),
        None,
    )?;
    pass.wall_mem = Some(wall_mem);
    dev.bind_image_memory(wall_image, wall_mem, 0)?;

    // the staging buffer with the wallpaper's pixels
    let pixels = wallpaper.as_raw();
    let (staging, staging_mem, staging_req) =
        host_buffer(gpu, pixels.len() as u64, vk::BufferUsageFlags::TRANSFER_SRC)?;
    pass.staging = Some(staging);
    pass.staging_mem = Some(staging_mem);
    let ptr = dev.map_memory(
        staging_mem,
        0,
        staging_req.size,
        vk::MemoryMapFlags::empty(),
    )?;
    std::ptr::copy_nonoverlapping(pixels.as_ptr(), ptr as *mut u8, pixels.len());
    dev.unmap_memory(staging_mem);

    // the uniforms
    let (ub, ub_mem, ub_req) =
        host_buffer(gpu, ubo.len() as u64, vk::BufferUsageFlags::UNIFORM_BUFFER)?;
    pass.ub = Some(ub);
    pass.ub_mem = Some(ub_mem);
    let ptr = dev.map_memory(ub_mem, 0, ub_req.size, vk::MemoryMapFlags::empty())?;
    std::ptr::copy_nonoverlapping(ubo.as_ptr(), ptr as *mut u8, ubo.len());
    dev.unmap_memory(ub_mem);

    // the picture the tool wrote out of the frame
    let readback_size = (width as u64) * (height as u64) * 4;
    let (readback, readback_mem, rb_req) =
        host_buffer(gpu, readback_size, vk::BufferUsageFlags::TRANSFER_DST)?;
    pass.readback = Some(readback);
    pass.readback_mem = Some(readback_mem);

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
    let set_layout = dev.create_descriptor_set_layout(
        &vk::DescriptorSetLayoutCreateInfo::default().bindings(&bindings),
        None,
    )?;
    pass.set_layout = Some(set_layout);
    let pool = dev.create_descriptor_pool(
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
    pass.pool = Some(pool);
    let layouts = [set_layout];
    let set = dev
        .allocate_descriptor_sets(
            &vk::DescriptorSetAllocateInfo::default()
                .descriptor_pool(pool)
                .set_layouts(&layouts),
        )?
        .into_iter()
        .next()
        .ok_or_else(|| anyhow!("Vulkan returned no descriptor set"))?;

    let sampler = dev.create_sampler(
        &vk::SamplerCreateInfo::default()
            .mag_filter(vk::Filter::LINEAR)
            .min_filter(vk::Filter::LINEAR)
            .address_mode_u(vk::SamplerAddressMode::CLAMP_TO_EDGE)
            .address_mode_v(vk::SamplerAddressMode::CLAMP_TO_EDGE)
            .address_mode_w(vk::SamplerAddressMode::CLAMP_TO_EDGE),
        None,
    )?;
    pass.sampler = Some(sampler);

    let wall_view = dev.create_image_view(
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
    )?;
    pass.wall_view = Some(wall_view);

    let ub_info = [vk::DescriptorBufferInfo::default()
        .buffer(ub)
        .offset(0)
        .range(ub_req.size)];
    let wall_info = [vk::DescriptorImageInfo::default()
        .image_layout(vk::ImageLayout::GENERAL)
        .image_view(wall_view)
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
    dev.update_descriptor_sets(&writes, &[]);

    // the pipeline
    let bytes = std::fs::read(shader_spv)
        .with_context(|| format!("reading SPIR-V {}", shader_spv.display()))?;
    if bytes.len() % 4 != 0 || bytes.is_empty() {
        return Err(anyhow!(
            "{} is not a whole number of SPIR-V words ({} bytes)",
            shader_spv.display(),
            bytes.len()
        ));
    }
    let code: Vec<u32> = bytes
        .chunks_exact(4)
        .map(|w| u32::from_le_bytes([w[0], w[1], w[2], w[3]]))
        .collect();
    let module =
        dev.create_shader_module(&vk::ShaderModuleCreateInfo::default().code(&code), None)?;
    pass.module = Some(module);
    let stage = vk::PipelineShaderStageCreateInfo::default()
        .stage(vk::ShaderStageFlags::COMPUTE)
        .module(module)
        .name(CStr::from_bytes_with_nul(b"main\0")?);
    let pipeline_layout = dev.create_pipeline_layout(
        &vk::PipelineLayoutCreateInfo::default().set_layouts(&layouts),
        None,
    )?;
    pass.pipeline_layout = Some(pipeline_layout);
    let pipeline = dev
        .create_compute_pipelines(
            vk::PipelineCache::null(),
            &[vk::ComputePipelineCreateInfo::default()
                .stage(stage)
                .layout(pipeline_layout)],
            None,
        )
        .map_err(|(_, e)| e)?
        .into_iter()
        .next()
        .ok_or_else(|| anyhow!("Vulkan returned no compute pipeline"))?;
    pass.pipeline = Some(pipeline);

    // one command buffer: upload, run, read back
    let command_pool = dev.create_command_pool(
        &vk::CommandPoolCreateInfo::default().queue_family_index(gpu.queue_family),
        None,
    )?;
    pass.command_pool = Some(command_pool);
    let cmd = dev
        .allocate_command_buffers(
            &vk::CommandBufferAllocateInfo::default()
                .command_pool(command_pool)
                .level(vk::CommandBufferLevel::PRIMARY)
                .command_buffer_count(1),
        )?
        .into_iter()
        .next()
        .ok_or_else(|| anyhow!("Vulkan returned no command buffer"))?;
    dev.begin_command_buffer(
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
    dev.cmd_pipeline_barrier(
        cmd,
        vk::PipelineStageFlags::TOP_OF_PIPE,
        vk::PipelineStageFlags::TRANSFER | vk::PipelineStageFlags::COMPUTE_SHADER,
        vk::DependencyFlags::empty(),
        &[],
        &[],
        &[to_general, wall_to_general],
    );

    dev.cmd_copy_buffer_to_image(
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
    // The copy above wrote the wallpaper through the transfer path; the shader
    // reads it through the texture path. Without a memory dependency here the
    // readback can catch the image half-written — same input, different frame.
    let wall_ready = vk::ImageMemoryBarrier::default()
        .old_layout(vk::ImageLayout::GENERAL)
        .new_layout(vk::ImageLayout::GENERAL)
        .src_access_mask(vk::AccessFlags::TRANSFER_WRITE)
        .dst_access_mask(vk::AccessFlags::SHADER_READ)
        .src_queue_family_index(vk::QUEUE_FAMILY_IGNORED)
        .dst_queue_family_index(vk::QUEUE_FAMILY_IGNORED)
        .image(wall_image)
        .subresource_range(vk::ImageSubresourceRange {
            aspect_mask: vk::ImageAspectFlags::COLOR,
            level_count: 1,
            layer_count: 1,
            ..Default::default()
        });
    dev.cmd_pipeline_barrier(
        cmd,
        vk::PipelineStageFlags::TRANSFER,
        vk::PipelineStageFlags::COMPUTE_SHADER,
        vk::DependencyFlags::empty(),
        &[],
        &[],
        &[wall_ready],
    );

    dev.cmd_bind_pipeline(cmd, vk::PipelineBindPoint::COMPUTE, pipeline);
    dev.cmd_bind_descriptor_sets(
        cmd,
        vk::PipelineBindPoint::COMPUTE,
        pipeline_layout,
        0,
        &[set],
        &[],
    );
    dev.cmd_dispatch(cmd, width.div_ceil(8), height.div_ceil(8), 1);

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
    dev.cmd_pipeline_barrier(
        cmd,
        vk::PipelineStageFlags::COMPUTE_SHADER,
        vk::PipelineStageFlags::TRANSFER,
        vk::DependencyFlags::empty(),
        &[],
        &[],
        &[out_to_transfer],
    );
    dev.cmd_copy_image_to_buffer(
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
    dev.end_command_buffer(cmd)?;

    let cmds = [cmd];
    let submit = vk::SubmitInfo::default().command_buffers(&cmds);
    dev.queue_submit(gpu.queue, &[submit], vk::Fence::null())?;
    dev.queue_wait_idle(gpu.queue)?;

    let ptr = dev.map_memory(readback_mem, 0, rb_req.size, vk::MemoryMapFlags::empty())?;
    let mut rgba = vec![0u8; readback_size as usize];
    std::ptr::copy_nonoverlapping(ptr as *const u8, rgba.as_mut_ptr(), rgba.len());
    dev.unmap_memory(readback_mem);

    Ok(Frame {
        width,
        height,
        rgba,
    })
}

/// A host-visible, host-coherent buffer of `size` bytes. If the memory
/// allocation fails, the just-created buffer is destroyed before returning.
unsafe fn host_buffer(
    gpu: &Gpu,
    size: u64,
    usage: vk::BufferUsageFlags,
) -> Result<(vk::Buffer, vk::DeviceMemory, vk::MemoryRequirements)> {
    let dev = &gpu.device;
    let buffer = dev.create_buffer(
        &vk::BufferCreateInfo::default()
            .size(size)
            .usage(usage)
            .sharing_mode(vk::SharingMode::EXCLUSIVE),
        None,
    )?;
    let req = dev.get_buffer_memory_requirements(buffer);
    let memory = match dev.allocate_memory(
        &vk::MemoryAllocateInfo::default()
            .allocation_size(req.size)
            .memory_type_index(gpu.memory_type(
                req.memory_type_bits,
                vk::MemoryPropertyFlags::HOST_VISIBLE | vk::MemoryPropertyFlags::HOST_COHERENT,
            )?),
        None,
    ) {
        Ok(memory) => memory,
        Err(e) => {
            dev.destroy_buffer(buffer, None);
            return Err(e.into());
        }
    };
    dev.bind_buffer_memory(buffer, memory, 0)?;
    Ok((buffer, memory, req))
}
