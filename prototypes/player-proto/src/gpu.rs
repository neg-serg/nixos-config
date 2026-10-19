//! Vulkan renderer: instance/device/swapchain, quad batching, glyph atlas and album art.
//!
//! One vertex layout and one vertex shader serve three fragment stages: shapes (SDF rounded
//! boxes with gradients and soft shadows), text (glyph atlas alpha) and images (album art with
//! rounded corners). Draw calls are batched by kind + scissor, so a full UI frame is a handful
//! of `vkCmdDraw`. Startup cost lives in vkCreateInstance/vkCreateDevice and the first present,
//! not in pipeline count.

use std::sync::atomic::{AtomicBool, Ordering};

use ash::vk;
use raw_window_handle::{HasDisplayHandle, HasWindowHandle};

use crate::scene::{Atlas, Batch, DrawList, Kind, ATLAS_H, ATLAS_W, MAX_VERTICES, VERTEX_SIZE};

const VERTEX_SHADER: &[u8] = include_bytes!("../shaders/ui.vert.spv");
const SHAPE_FRAGMENT: &[u8] = include_bytes!("../shaders/solid.frag.spv");
const TEXT_FRAGMENT: &[u8] = include_bytes!("../shaders/text.frag.spv");
const IMAGE_FRAGMENT: &[u8] = include_bytes!("../shaders/image.frag.spv");

/// Set by the caller when an HDR10 swapchain should be requested.
static HDR_REQUESTED: AtomicBool = AtomicBool::new(false);

pub fn request_hdr(on: bool) {
    HDR_REQUESTED.store(on, Ordering::Relaxed);
}

pub struct Gpu {
    _entry: ash::Entry,
    instance: ash::Instance,
    surface_fn: ash::khr::surface::Instance,
    surface: vk::SurfaceKHR,
    phys: vk::PhysicalDevice,
    color_space: vk::ColorSpaceKHR,
    device: ash::Device,
    swapchain_fn: ash::khr::swapchain::Device,
    mem_props: vk::PhysicalDeviceMemoryProperties,
    swapchain: vk::SwapchainKHR,
    views: Vec<vk::ImageView>,
    swapchain_images: Vec<vk::Image>,
    framebuffers: Vec<vk::Framebuffer>,
    render_pass: vk::RenderPass,
    pub extent: vk::Extent2D,
    /// Capture size for offscreen renders; `None` follows the swapchain extent.
    capture_size: Option<(u32, u32)>,
    pub format: vk::Format,
    layout: vk::PipelineLayout,
    pipeline_shape: vk::Pipeline,
    pipeline_text: vk::Pipeline,
    pipeline_image: vk::Pipeline,
    desc_pool: vk::DescriptorPool,
    set_atlas: vk::DescriptorSet,
    set_art: vk::DescriptorSet,
    atlas_image: vk::Image,
    atlas_memory: vk::DeviceMemory,
    atlas_view: vk::ImageView,
    atlas_layout: vk::ImageLayout,
    sampler: vk::Sampler,
    art_image: vk::Image,
    art_memory: vk::DeviceMemory,
    art_view: vk::ImageView,
    art_size: (u32, u32),
    art_uploaded: bool,
    vertex_buffer: vk::Buffer,
    /// Separate vertex buffer for offscreen captures: the frame's buffer is still referenced by
    /// the compositor's present when a capture runs, so sharing it corrupts the capture
    /// (observed as doubled/shifted UI in the PPM).
    capture_vbuf: vk::Buffer,
    capture_vmem: vk::DeviceMemory,
    vertex_memory: vk::DeviceMemory,
    vertex_ptr: *mut u8,
    graphics_queue: vk::Queue,
    present_queue: vk::Queue,
    pool: vk::CommandPool,
    cmd: vk::CommandBuffer,
    capture_cmd: vk::CommandBuffer,
    acquire_sem: vk::Semaphore,
    render_sem: vk::Semaphore,
    in_flight: vk::Fence,
    /// Index of the swapchain image handed to the compositor most recently.
    pub last_present_index: u32,
    /// Set when acquire/present reported SUBOPTIMAL or OUT_OF_DATE; the app rebuilds and retries.
    pub needs_resize: bool,
    /// Resolution passed to the vertex shader. With a HiDPI surface the UI is laid out in
    /// logical units, so this is the *logical* size while the swapchain stays physical.
    push_res: [f32; 2],
    /// Coverage gamma for glyph blending; 1.0 = raw linear blend (thin text on an SRGB target).
    text_gamma: f32,
}

pub fn find_memory_type(
    props: &vk::PhysicalDeviceMemoryProperties,
    req: u32,
    flags: vk::MemoryPropertyFlags,
) -> Option<u32> {
    (0..props.memory_type_count).find(|&i| {
        let bits = 1 << i;
        req & bits != 0
            && props.memory_types[i as usize]
                .property_flags
                .contains(flags)
    })
}

struct ImageAlloc {
    image: vk::Image,
    memory: vk::DeviceMemory,
    view: vk::ImageView,
}

impl Gpu {
    pub unsafe fn create_buffer(
        device: &ash::Device,
        mem_props: &vk::PhysicalDeviceMemoryProperties,
        size: u64,
        usage: vk::BufferUsageFlags,
        flags: vk::MemoryPropertyFlags,
    ) -> Option<(vk::Buffer, vk::DeviceMemory)> {
        let buffer = device
            .create_buffer(
                &vk::BufferCreateInfo::default()
                    .size(size)
                    .usage(usage)
                    .sharing_mode(vk::SharingMode::EXCLUSIVE),
                None,
            )
            .ok()?;
        let req = device.get_buffer_memory_requirements(buffer);
        let idx = find_memory_type(mem_props, req.memory_type_bits, flags)?;
        let memory = device
            .allocate_memory(
                &vk::MemoryAllocateInfo::default()
                    .allocation_size(req.size)
                    .memory_type_index(idx),
                None,
            )
            .ok()?;
        device.bind_buffer_memory(buffer, memory, 0).ok()?;
        Some((buffer, memory))
    }

    unsafe fn create_image(
        device: &ash::Device,
        mem_props: &vk::PhysicalDeviceMemoryProperties,
        w: u32,
        h: u32,
        format: vk::Format,
        usage: vk::ImageUsageFlags,
    ) -> Option<ImageAlloc> {
        let image = device
            .create_image(
                &vk::ImageCreateInfo::default()
                    .image_type(vk::ImageType::TYPE_2D)
                    .format(format)
                    .extent(vk::Extent3D {
                        width: w,
                        height: h,
                        depth: 1,
                    })
                    .mip_levels(1)
                    .array_layers(1)
                    .samples(vk::SampleCountFlags::TYPE_1)
                    .tiling(vk::ImageTiling::OPTIMAL)
                    .usage(usage)
                    .sharing_mode(vk::SharingMode::EXCLUSIVE)
                    .initial_layout(vk::ImageLayout::UNDEFINED),
                None,
            )
            .ok()?;
        let req = device.get_image_memory_requirements(image);
        let idx = find_memory_type(
            mem_props,
            req.memory_type_bits,
            vk::MemoryPropertyFlags::DEVICE_LOCAL,
        )?;
        let memory = device
            .allocate_memory(
                &vk::MemoryAllocateInfo::default()
                    .allocation_size(req.size)
                    .memory_type_index(idx),
                None,
            )
            .ok()?;
        device.bind_image_memory(image, memory, 0).ok()?;
        let view = device
            .create_image_view(
                &vk::ImageViewCreateInfo::default()
                    .image(image)
                    .view_type(vk::ImageViewType::TYPE_2D)
                    .format(format)
                    .subresource_range(
                        vk::ImageSubresourceRange::default()
                            .aspect_mask(vk::ImageAspectFlags::COLOR)
                            .level_count(1)
                            .layer_count(1),
                    ),
                None,
            )
            .ok()?;
        Some(ImageAlloc {
            image,
            memory,
            view,
        })
    }

    unsafe fn destroy_image(&self, img: ImageAlloc) {
        self.device.destroy_image_view(img.view, None);
        self.device.destroy_image(img.image, None);
        self.device.free_memory(img.memory, None);
    }

    /// Rebuild the swapchain for a new surface size. Wayland sends the first configure at scale
    /// 1 and then corrects to the monitor scale (2 on a HiDPI panel), so without this the buffer
    /// stops matching the surface and the compositor stops showing the window.
    pub unsafe fn recreate_swapchain(&mut self, width: u32, height: u32) -> Result<(), vk::Result> {
        if width == 0 || height == 0 {
            return Ok(());
        }
        if (width, height) == (self.extent.width, self.extent.height) {
            return Ok(());
        }
        self.device.device_wait_idle()?;
        for fb in self.framebuffers.drain(..) {
            self.device.destroy_framebuffer(fb, None);
        }
        for v in self.views.drain(..) {
            self.device.destroy_image_view(v, None);
        }
        self.swapchain_fn.destroy_swapchain(self.swapchain, None);

        let caps = self
            .surface_fn
            .get_physical_device_surface_capabilities(self.phys, self.surface)?;
        // Prefer what the compositor dictates: chasing the window size instead oscillates
        // (Hyprland keeps re-configuring when the buffer size disagrees with the tile).
        let mut extent = if caps.current_extent.width != u32::MAX {
            caps.current_extent
        } else {
            vk::Extent2D { width, height }
        };
        if std::env::var("PLAYER_DEBUG_RESIZE").is_ok() {
            eprintln!(
                "[resize] requested={}x{} current_extent={}x{} -> {}x{}",
                width,
                height,
                caps.current_extent.width,
                caps.current_extent.height,
                extent.width,
                extent.height
            );
        }
        extent.width = extent
            .width
            .clamp(caps.min_image_extent.width, caps.max_image_extent.width);
        extent.height = extent
            .height
            .clamp(caps.min_image_extent.height, caps.max_image_extent.height);
        let image_count = (caps.min_image_count + 1).min(if caps.max_image_count == 0 {
            u32::MAX
        } else {
            caps.max_image_count
        });
        let swapchain = self.swapchain_fn.create_swapchain(
            &vk::SwapchainCreateInfoKHR::default()
                .surface(self.surface)
                .min_image_count(image_count)
                .image_format(self.format)
                .image_color_space(self.color_space)
                .image_extent(extent)
                .image_array_layers(1)
                .image_usage(vk::ImageUsageFlags::COLOR_ATTACHMENT)
                .image_sharing_mode(vk::SharingMode::EXCLUSIVE)
                .pre_transform(caps.current_transform)
                .composite_alpha(vk::CompositeAlphaFlagsKHR::OPAQUE)
                .present_mode(vk::PresentModeKHR::FIFO)
                .clipped(true),
            None,
        )?;
        let images = self.swapchain_fn.get_swapchain_images(swapchain)?;
        for img in &images {
            let view = self.device.create_image_view(
                &vk::ImageViewCreateInfo::default()
                    .image(*img)
                    .view_type(vk::ImageViewType::TYPE_2D)
                    .format(self.format)
                    .subresource_range(
                        vk::ImageSubresourceRange::default()
                            .aspect_mask(vk::ImageAspectFlags::COLOR)
                            .level_count(1)
                            .layer_count(1),
                    ),
                None,
            )?;
            self.views.push(view);
            let fb = self.device.create_framebuffer(
                &vk::FramebufferCreateInfo::default()
                    .render_pass(self.render_pass)
                    .attachments(std::slice::from_ref(&view))
                    .width(extent.width)
                    .height(extent.height)
                    .layers(1),
                None,
            )?;
            self.framebuffers.push(fb);
        }
        self.swapchain = swapchain;
        self.extent = extent;
        Ok(())
    }

    pub fn destroy(&mut self) {
        unsafe {
            let _ = self.device.device_wait_idle();
            self.device.unmap_memory(self.vertex_memory);
            self.device.destroy_buffer(self.vertex_buffer, None);
            self.device.free_memory(self.vertex_memory, None);
            self.device.destroy_buffer(self.capture_vbuf, None);
            self.device.free_memory(self.capture_vmem, None);
            self.device.destroy_sampler(self.sampler, None);
            let art = ImageAlloc {
                image: self.art_image,
                memory: self.art_memory,
                view: self.art_view,
            };
            self.destroy_image(art);
            let atlas = ImageAlloc {
                image: self.atlas_image,
                memory: self.atlas_memory,
                view: self.atlas_view,
            };
            self.destroy_image(atlas);
            self.device.destroy_descriptor_pool(self.desc_pool, None);
            self.device.destroy_pipeline(self.pipeline_shape, None);
            self.device.destroy_pipeline(self.pipeline_text, None);
            self.device.destroy_pipeline(self.pipeline_image, None);
            self.device.destroy_pipeline_layout(self.layout, None);
            self.device.destroy_fence(self.in_flight, None);
            self.device.destroy_semaphore(self.render_sem, None);
            self.device.destroy_semaphore(self.acquire_sem, None);
            self.device.destroy_command_pool(self.pool, None);
            for fb in self.framebuffers.drain(..) {
                self.device.destroy_framebuffer(fb, None);
            }
            for v in self.views.drain(..) {
                self.device.destroy_image_view(v, None);
            }
            self.swapchain_fn.destroy_swapchain(self.swapchain, None);
            self.device.destroy_render_pass(self.render_pass, None);
            self.device.destroy_device(None);
            self.surface_fn.destroy_surface(self.surface, None);
            self.instance.destroy_instance(None);
        }
    }

    /// Upload the CPU glyph atlas into its GPU image.
    /// Wait until the GPU is done with everything previously submitted. Reusing `self.cmd`
    /// while a submission still references it is undefined behaviour: llvmpipe tolerates it,
    /// RADV answers with VK_ERROR_DEVICE_LOST (observed on the first offscreen capture).
    unsafe fn wait_idle(&self) -> Result<(), vk::Result> {
        // llvmpipe executes submissions on a worker thread and its present path can still hold
        // the vertex buffer after the fence signals, so captures take the device-wide wait.
        self.device.device_wait_idle()?;
        Ok(())
    }

    pub unsafe fn upload_atlas(&mut self, atlas: &Atlas) -> Result<(), vk::Result> {
        self.wait_idle()?;
        let bytes = atlas.pixels.clone();
        let size = bytes.len() as u64;
        let (staging, staging_mem) = Gpu::create_buffer(
            &self.device,
            &self.mem_props,
            size,
            vk::BufferUsageFlags::TRANSFER_SRC,
            vk::MemoryPropertyFlags::HOST_VISIBLE | vk::MemoryPropertyFlags::HOST_COHERENT,
        )
        .ok_or(vk::Result::ERROR_OUT_OF_DEVICE_MEMORY)?;
        let ptr =
            self.device
                .map_memory(staging_mem, 0, vk::WHOLE_SIZE, vk::MemoryMapFlags::empty())?;
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), ptr as *mut u8, size as usize);
        self.device.unmap_memory(staging_mem);

        self.device
            .reset_command_buffer(self.cmd, vk::CommandBufferResetFlags::empty())?;
        self.device
            .begin_command_buffer(self.cmd, &vk::CommandBufferBeginInfo::default())?;
        let from = std::mem::replace(
            &mut self.atlas_layout,
            vk::ImageLayout::TRANSFER_DST_OPTIMAL,
        );
        let to_dst = vk::ImageMemoryBarrier::default()
            .old_layout(from)
            .new_layout(vk::ImageLayout::TRANSFER_DST_OPTIMAL)
            .src_queue_family_index(vk::QUEUE_FAMILY_IGNORED)
            .dst_queue_family_index(vk::QUEUE_FAMILY_IGNORED)
            .image(self.atlas_image)
            .subresource_range(
                vk::ImageSubresourceRange::default()
                    .aspect_mask(vk::ImageAspectFlags::COLOR)
                    .level_count(1)
                    .layer_count(1),
            )
            .src_access_mask(if from == vk::ImageLayout::UNDEFINED {
                vk::AccessFlags::empty()
            } else {
                vk::AccessFlags::SHADER_READ
            })
            .dst_access_mask(vk::AccessFlags::TRANSFER_WRITE);
        self.device.cmd_pipeline_barrier(
            self.cmd,
            if from == vk::ImageLayout::UNDEFINED {
                vk::PipelineStageFlags::TOP_OF_PIPE
            } else {
                vk::PipelineStageFlags::FRAGMENT_SHADER
            },
            vk::PipelineStageFlags::TRANSFER,
            vk::DependencyFlags::empty(),
            &[],
            &[],
            &[to_dst],
        );
        self.device.cmd_copy_buffer_to_image(
            self.cmd,
            staging,
            self.atlas_image,
            vk::ImageLayout::TRANSFER_DST_OPTIMAL,
            &[vk::BufferImageCopy::default()
                .image_subresource(
                    vk::ImageSubresourceLayers::default()
                        .aspect_mask(vk::ImageAspectFlags::COLOR)
                        .layer_count(1),
                )
                .image_extent(vk::Extent3D {
                    width: ATLAS_W,
                    height: ATLAS_H,
                    depth: 1,
                })],
        );
        let to_shader = vk::ImageMemoryBarrier::default()
            .old_layout(vk::ImageLayout::TRANSFER_DST_OPTIMAL)
            .new_layout(vk::ImageLayout::SHADER_READ_ONLY_OPTIMAL)
            .src_queue_family_index(vk::QUEUE_FAMILY_IGNORED)
            .dst_queue_family_index(vk::QUEUE_FAMILY_IGNORED)
            .image(self.atlas_image)
            .subresource_range(
                vk::ImageSubresourceRange::default()
                    .aspect_mask(vk::ImageAspectFlags::COLOR)
                    .level_count(1)
                    .layer_count(1),
            )
            .src_access_mask(vk::AccessFlags::TRANSFER_WRITE)
            .dst_access_mask(vk::AccessFlags::SHADER_READ);
        self.device.cmd_pipeline_barrier(
            self.cmd,
            vk::PipelineStageFlags::TRANSFER,
            vk::PipelineStageFlags::FRAGMENT_SHADER,
            vk::DependencyFlags::empty(),
            &[],
            &[],
            &[to_shader],
        );
        self.device.end_command_buffer(self.cmd)?;
        let cmds = [self.cmd];
        let submit = vk::SubmitInfo::default().command_buffers(&cmds);
        self.device
            .queue_submit(self.graphics_queue, &[submit], vk::Fence::null())?;
        self.device.queue_wait_idle(self.graphics_queue)?;
        self.atlas_layout = vk::ImageLayout::SHADER_READ_ONLY_OPTIMAL;
        self.device.destroy_buffer(staging, None);
        self.device.free_memory(staging_mem, None);
        Ok(())
    }

    /// Upload album art (RGBA8). Recreates the texture when the size changes.
    pub unsafe fn upload_art(&mut self, w: u32, h: u32, rgba: &[u8]) -> Result<(), vk::Result> {
        self.wait_idle()?;
        if w == 0 || h == 0 {
            return Ok(());
        }
        let size = (w * h * 4) as u64;
        if rgba.len() as u64 != size {
            return Err(vk::Result::ERROR_INITIALIZATION_FAILED);
        }
        if (w, h) != self.art_size {
            let old = ImageAlloc {
                image: self.art_image,
                memory: self.art_memory,
                view: self.art_view,
            };
            self.destroy_image(old);
            let fresh = Gpu::create_image(
                &self.device,
                &self.mem_props,
                w,
                h,
                vk::Format::R8G8B8A8_SRGB,
                vk::ImageUsageFlags::SAMPLED | vk::ImageUsageFlags::TRANSFER_DST,
            )
            .ok_or(vk::Result::ERROR_OUT_OF_DEVICE_MEMORY)?;
            self.art_image = fresh.image;
            self.art_memory = fresh.memory;
            self.art_view = fresh.view;
            self.art_size = (w, h);
            let image_info = [vk::DescriptorImageInfo::default()
                .image_layout(vk::ImageLayout::SHADER_READ_ONLY_OPTIMAL)
                .image_view(self.art_view)
                .sampler(self.sampler)];
            self.device.update_descriptor_sets(
                &[vk::WriteDescriptorSet::default()
                    .dst_set(self.set_art)
                    .dst_binding(0)
                    .descriptor_type(vk::DescriptorType::COMBINED_IMAGE_SAMPLER)
                    .image_info(&image_info)],
                &[],
            );
        }
        let (staging, staging_mem) = Gpu::create_buffer(
            &self.device,
            &self.mem_props,
            size,
            vk::BufferUsageFlags::TRANSFER_SRC,
            vk::MemoryPropertyFlags::HOST_VISIBLE | vk::MemoryPropertyFlags::HOST_COHERENT,
        )
        .ok_or(vk::Result::ERROR_OUT_OF_DEVICE_MEMORY)?;
        let ptr =
            self.device
                .map_memory(staging_mem, 0, vk::WHOLE_SIZE, vk::MemoryMapFlags::empty())?;
        std::ptr::copy_nonoverlapping(rgba.as_ptr(), ptr as *mut u8, size as usize);
        self.device.unmap_memory(staging_mem);

        self.device
            .reset_command_buffer(self.cmd, vk::CommandBufferResetFlags::empty())?;
        self.device
            .begin_command_buffer(self.cmd, &vk::CommandBufferBeginInfo::default())?;
        let to_dst = vk::ImageMemoryBarrier::default()
            .old_layout(vk::ImageLayout::SHADER_READ_ONLY_OPTIMAL)
            .new_layout(vk::ImageLayout::TRANSFER_DST_OPTIMAL)
            .src_queue_family_index(vk::QUEUE_FAMILY_IGNORED)
            .dst_queue_family_index(vk::QUEUE_FAMILY_IGNORED)
            .image(self.art_image)
            .subresource_range(
                vk::ImageSubresourceRange::default()
                    .aspect_mask(vk::ImageAspectFlags::COLOR)
                    .level_count(1)
                    .layer_count(1),
            )
            .src_access_mask(vk::AccessFlags::SHADER_READ)
            .dst_access_mask(vk::AccessFlags::TRANSFER_WRITE);
        let first_use = vk::ImageMemoryBarrier::default()
            .old_layout(vk::ImageLayout::UNDEFINED)
            .new_layout(vk::ImageLayout::TRANSFER_DST_OPTIMAL)
            .src_queue_family_index(vk::QUEUE_FAMILY_IGNORED)
            .dst_queue_family_index(vk::QUEUE_FAMILY_IGNORED)
            .image(self.art_image)
            .subresource_range(
                vk::ImageSubresourceRange::default()
                    .aspect_mask(vk::ImageAspectFlags::COLOR)
                    .level_count(1)
                    .layer_count(1),
            )
            .dst_access_mask(vk::AccessFlags::TRANSFER_WRITE);
        let barrier = if self.art_uploaded { to_dst } else { first_use };
        self.device.cmd_pipeline_barrier(
            self.cmd,
            vk::PipelineStageFlags::FRAGMENT_SHADER,
            vk::PipelineStageFlags::TRANSFER,
            vk::DependencyFlags::empty(),
            &[],
            &[],
            &[barrier],
        );
        self.device.cmd_copy_buffer_to_image(
            self.cmd,
            staging,
            self.art_image,
            vk::ImageLayout::TRANSFER_DST_OPTIMAL,
            &[vk::BufferImageCopy::default()
                .image_subresource(
                    vk::ImageSubresourceLayers::default()
                        .aspect_mask(vk::ImageAspectFlags::COLOR)
                        .layer_count(1),
                )
                .image_extent(vk::Extent3D {
                    width: w,
                    height: h,
                    depth: 1,
                })],
        );
        let to_shader = vk::ImageMemoryBarrier::default()
            .old_layout(vk::ImageLayout::TRANSFER_DST_OPTIMAL)
            .new_layout(vk::ImageLayout::SHADER_READ_ONLY_OPTIMAL)
            .src_queue_family_index(vk::QUEUE_FAMILY_IGNORED)
            .dst_queue_family_index(vk::QUEUE_FAMILY_IGNORED)
            .image(self.art_image)
            .subresource_range(
                vk::ImageSubresourceRange::default()
                    .aspect_mask(vk::ImageAspectFlags::COLOR)
                    .level_count(1)
                    .layer_count(1),
            )
            .src_access_mask(vk::AccessFlags::TRANSFER_WRITE)
            .dst_access_mask(vk::AccessFlags::SHADER_READ);
        self.device.cmd_pipeline_barrier(
            self.cmd,
            vk::PipelineStageFlags::TRANSFER,
            vk::PipelineStageFlags::FRAGMENT_SHADER,
            vk::DependencyFlags::empty(),
            &[],
            &[],
            &[to_shader],
        );
        self.device.end_command_buffer(self.cmd)?;
        let cmds = [self.cmd];
        let submit = vk::SubmitInfo::default().command_buffers(&cmds);
        self.device
            .queue_submit(self.graphics_queue, &[submit], vk::Fence::null())?;
        self.device.queue_wait_idle(self.graphics_queue)?;
        self.art_uploaded = true;
        self.device.destroy_buffer(staging, None);
        self.device.free_memory(staging_mem, None);
        Ok(())
    }
}

pub struct InitTiming<'a> {
    pub timing: &'a mut crate::Timing,
}

/// `forced_size` overrides the swapchain extent when the surface lets the application choose
/// (`currentExtent == UINT32_MAX`). Kept equal to the capture size on purpose: llvmpipe crashes
/// in its image->buffer copy path when one render pass is used with framebuffers of two
/// different sizes (reproduced with a 1440x900 capture against a tiled 960x1055 swapchain).
pub fn create_gpu(
    window: &winit::window::Window,
    t: &mut InitTiming<'_>,
    forced_size: Option<(u32, u32)>,
) -> Option<Gpu> {
    unsafe {
        // NixOS has no ld.so.cache: load the loader by absolute path, fall back to plain dlopen.
        let entry = ash::Entry::load_from("/run/current-system/sw/lib/libvulkan.so.1")
            .or_else(|_| ash::Entry::load())
            .ok()?;

        let display = window.display_handle().ok()?.as_raw();
        let wh = window.window_handle().ok()?.as_raw();
        let extensions = ash_window::enumerate_required_extensions(display)
            .ok()?
            .to_vec();

        let app_info = vk::ApplicationInfo::default()
            .application_name(c"player")
            .application_version(1)
            .api_version(vk::make_api_version(0, 1, 2, 0));
        let instance_info = vk::InstanceCreateInfo::default()
            .application_info(&app_info)
            .enabled_extension_names(&extensions);
        let instance = entry.create_instance(&instance_info, None).ok()?;
        t.timing.mark("instance");

        let surface_fn = ash::khr::surface::Instance::new(&entry, &instance);
        let surface = ash_window::create_surface(&entry, &instance, display, wh, None).ok()?;
        t.timing.mark("surface");

        let devices = instance.enumerate_physical_devices().ok()?;
        let mut chosen = None;
        for d in devices {
            let props = instance.get_physical_device_properties(d);
            let fams = instance.get_physical_device_queue_family_properties(d);
            let mut gfx = None;
            let mut present = None;
            for (i, fam) in fams.iter().enumerate() {
                let i = i as u32;
                if fam.queue_flags.contains(vk::QueueFlags::GRAPHICS) && gfx.is_none() {
                    gfx = Some(i);
                }
                if surface_fn
                    .get_physical_device_surface_support(d, i, surface)
                    .unwrap_or(false)
                {
                    present = Some(i);
                }
            }
            if let (Some(g), Some(p)) = (gfx, present) {
                let is_cpu = props.device_type == vk::PhysicalDeviceType::CPU;
                let name = props
                    .device_name_as_c_str()
                    .map(|s| s.to_string_lossy().into_owned())
                    .unwrap_or_default();
                println!("device: {name} (cpu={is_cpu})");
                if chosen.is_none() || !is_cpu {
                    chosen = Some((d, g, p, is_cpu));
                    if !is_cpu {
                        break;
                    }
                }
            }
        }
        let (phys, gfx_family, present_family, _) = chosen?;
        let mem_props = instance.get_physical_device_memory_properties(phys);
        t.timing.mark("device_enum");

        let available = instance
            .enumerate_device_extension_properties(phys)
            .unwrap_or_default();
        let has_hdr_metadata = available.iter().any(|e| {
            e.extension_name_as_c_str()
                .map(|n| n == ash::ext::hdr_metadata::NAME)
                .unwrap_or(false)
        });
        let mut device_exts: Vec<*const std::os::raw::c_char> =
            vec![ash::khr::swapchain::NAME.as_ptr()];
        if has_hdr_metadata {
            device_exts.push(ash::ext::hdr_metadata::NAME.as_ptr());
        }

        let priorities = [1.0f32];
        let mut families = vec![vk::DeviceQueueCreateInfo::default()
            .queue_family_index(gfx_family)
            .queue_priorities(&priorities)];
        if present_family != gfx_family {
            families.push(
                vk::DeviceQueueCreateInfo::default()
                    .queue_family_index(present_family)
                    .queue_priorities(&priorities),
            );
        }
        let device = instance
            .create_device(
                phys,
                &vk::DeviceCreateInfo::default()
                    .queue_create_infos(&families)
                    .enabled_extension_names(&device_exts),
                None,
            )
            .ok()?;
        t.timing.mark("device");

        let swapchain_fn = ash::khr::swapchain::Device::new(&instance, &device);
        let caps = surface_fn
            .get_physical_device_surface_capabilities(phys, surface)
            .ok()?;
        let formats = surface_fn
            .get_physical_device_surface_formats(phys, surface)
            .ok()?;
        let modes = surface_fn
            .get_physical_device_surface_present_modes(phys, surface)
            .ok()?;
        let hdr_wanted = HDR_REQUESTED.load(Ordering::Relaxed);
        let hdr_format = formats
            .iter()
            .find(|f| {
                matches!(
                    f.format,
                    vk::Format::A2B10G10R10_UNORM_PACK32 | vk::Format::A2R10G10B10_UNORM_PACK32
                ) && f.color_space == vk::ColorSpaceKHR::HDR10_ST2084_EXT
            })
            .copied();
        let sdr_format = || {
            formats
                .iter()
                .find(|f| {
                    f.format == vk::Format::B8G8R8A8_SRGB
                        && f.color_space == vk::ColorSpaceKHR::SRGB_NONLINEAR
                })
                .or_else(|| formats.first())
                .copied()
        };
        let format = if hdr_wanted {
            hdr_format.or_else(sdr_format)?
        } else {
            sdr_format()?
        };

        let size = window.inner_size();
        // A pinned capture size wins over the compositor: scripted runs need a fixed extent, and
        // llvmpipe crashes when an image->buffer copy crosses two different framebuffer sizes.
        let mut extent = match forced_size {
            Some((w, h)) => vk::Extent2D {
                width: w.max(1),
                height: h.max(1),
            },
            None => vk::Extent2D {
                width: if caps.current_extent.width == u32::MAX {
                    size.width.max(1)
                } else {
                    caps.current_extent.width
                },
                height: if caps.current_extent.height == u32::MAX {
                    size.height.max(1)
                } else {
                    caps.current_extent.height
                },
            },
        };
        extent.width = extent
            .width
            .clamp(caps.min_image_extent.width, caps.max_image_extent.width);
        extent.height = extent
            .height
            .clamp(caps.min_image_extent.height, caps.max_image_extent.height);
        let image_count = (caps.min_image_count + 1).min(if caps.max_image_count == 0 {
            u32::MAX
        } else {
            caps.max_image_count
        });

        let swapchain = swapchain_fn
            .create_swapchain(
                &vk::SwapchainCreateInfoKHR::default()
                    .surface(surface)
                    .min_image_count(image_count)
                    .image_format(format.format)
                    .image_color_space(format.color_space)
                    .image_extent(extent)
                    .image_array_layers(1)
                    .image_usage(vk::ImageUsageFlags::COLOR_ATTACHMENT)
                    .image_sharing_mode(vk::SharingMode::EXCLUSIVE)
                    .pre_transform(caps.current_transform)
                    .composite_alpha(vk::CompositeAlphaFlagsKHR::OPAQUE)
                    .present_mode(if modes.contains(&vk::PresentModeKHR::FIFO) {
                        vk::PresentModeKHR::FIFO
                    } else {
                        modes[0]
                    })
                    .clipped(true),
                None,
            )
            .ok()?;
        let images = swapchain_fn.get_swapchain_images(swapchain).ok()?;
        t.timing.mark("swapchain");

        let attach = [vk::AttachmentDescription::default()
            .format(format.format)
            .samples(vk::SampleCountFlags::TYPE_1)
            .load_op(vk::AttachmentLoadOp::CLEAR)
            .store_op(vk::AttachmentStoreOp::STORE)
            .stencil_load_op(vk::AttachmentLoadOp::DONT_CARE)
            .stencil_store_op(vk::AttachmentStoreOp::DONT_CARE)
            .initial_layout(vk::ImageLayout::UNDEFINED)
            .final_layout(vk::ImageLayout::PRESENT_SRC_KHR)];
        let color_ref = [vk::AttachmentReference::default()
            .attachment(0)
            .layout(vk::ImageLayout::COLOR_ATTACHMENT_OPTIMAL)];
        let subpass = [vk::SubpassDescription::default()
            .pipeline_bind_point(vk::PipelineBindPoint::GRAPHICS)
            .color_attachments(&color_ref)];
        let dep = [vk::SubpassDependency::default()
            .src_subpass(vk::SUBPASS_EXTERNAL)
            .dst_subpass(0)
            .src_stage_mask(vk::PipelineStageFlags::COLOR_ATTACHMENT_OUTPUT)
            .dst_stage_mask(vk::PipelineStageFlags::COLOR_ATTACHMENT_OUTPUT)
            .dst_access_mask(vk::AccessFlags::COLOR_ATTACHMENT_WRITE)];
        let render_pass = device
            .create_render_pass(
                &vk::RenderPassCreateInfo::default()
                    .attachments(&attach)
                    .subpasses(&subpass)
                    .dependencies(&dep),
                None,
            )
            .ok()?;

        let mut views = Vec::with_capacity(images.len());
        let mut framebuffers = Vec::with_capacity(images.len());
        for img in &images {
            let view = device
                .create_image_view(
                    &vk::ImageViewCreateInfo::default()
                        .image(*img)
                        .view_type(vk::ImageViewType::TYPE_2D)
                        .format(format.format)
                        .subresource_range(
                            vk::ImageSubresourceRange::default()
                                .aspect_mask(vk::ImageAspectFlags::COLOR)
                                .level_count(1)
                                .layer_count(1),
                        ),
                    None,
                )
                .ok()?;
            views.push(view);
            framebuffers.push(
                device
                    .create_framebuffer(
                        &vk::FramebufferCreateInfo::default()
                            .render_pass(render_pass)
                            .attachments(std::slice::from_ref(&view))
                            .width(extent.width)
                            .height(extent.height)
                            .layers(1),
                        None,
                    )
                    .ok()?,
            );
        }
        t.timing.mark("framebuffers");

        let atlas = Gpu::create_image(
            &device,
            &mem_props,
            ATLAS_W,
            ATLAS_H,
            vk::Format::R8_UNORM,
            vk::ImageUsageFlags::SAMPLED | vk::ImageUsageFlags::TRANSFER_DST,
        )?;
        let art = Gpu::create_image(
            &device,
            &mem_props,
            1,
            1,
            vk::Format::R8G8B8A8_SRGB,
            vk::ImageUsageFlags::SAMPLED | vk::ImageUsageFlags::TRANSFER_DST,
        )?;
        let sampler = device
            .create_sampler(
                &vk::SamplerCreateInfo::default()
                    .mag_filter(vk::Filter::LINEAR)
                    .min_filter(vk::Filter::LINEAR)
                    .address_mode_u(vk::SamplerAddressMode::CLAMP_TO_EDGE)
                    .address_mode_v(vk::SamplerAddressMode::CLAMP_TO_EDGE)
                    .address_mode_w(vk::SamplerAddressMode::CLAMP_TO_EDGE),
                None,
            )
            .ok()?;

        let binding = [vk::DescriptorSetLayoutBinding::default()
            .binding(0)
            .descriptor_type(vk::DescriptorType::COMBINED_IMAGE_SAMPLER)
            .descriptor_count(1)
            .stage_flags(vk::ShaderStageFlags::FRAGMENT)];
        let dsl = device
            .create_descriptor_set_layout(
                &vk::DescriptorSetLayoutCreateInfo::default().bindings(&binding),
                None,
            )
            .ok()?;
        let push = [vk::PushConstantRange::default()
            .stage_flags(vk::ShaderStageFlags::VERTEX | vk::ShaderStageFlags::FRAGMENT)
            .offset(0)
            .size(16)];
        let layout = device
            .create_pipeline_layout(
                &vk::PipelineLayoutCreateInfo::default()
                    .set_layouts(&[dsl])
                    .push_constant_ranges(&push),
                None,
            )
            .ok()?;
        let pool_sizes = [vk::DescriptorPoolSize::default()
            .ty(vk::DescriptorType::COMBINED_IMAGE_SAMPLER)
            .descriptor_count(4)];
        let desc_pool = device
            .create_descriptor_pool(
                &vk::DescriptorPoolCreateInfo::default()
                    .pool_sizes(&pool_sizes)
                    .max_sets(4),
                None,
            )
            .ok()?;
        let sets = device
            .allocate_descriptor_sets(
                &vk::DescriptorSetAllocateInfo::default()
                    .descriptor_pool(desc_pool)
                    .set_layouts(&[dsl, dsl]),
            )
            .ok()?;
        let (set_atlas, set_art) = (sets[0], sets[1]);
        let atlas_info = [vk::DescriptorImageInfo::default()
            .image_layout(vk::ImageLayout::SHADER_READ_ONLY_OPTIMAL)
            .image_view(atlas.view)
            .sampler(sampler)];
        device.update_descriptor_sets(
            &[vk::WriteDescriptorSet::default()
                .dst_set(set_atlas)
                .dst_binding(0)
                .descriptor_type(vk::DescriptorType::COMBINED_IMAGE_SAMPLER)
                .image_info(&atlas_info)],
            &[],
        );

        let make_pipeline = |frag: &[u8]| -> Option<vk::Pipeline> {
            let vert_code = ash::util::read_spv(&mut std::io::Cursor::new(VERTEX_SHADER)).ok()?;
            let vert_mod = device
                .create_shader_module(
                    &vk::ShaderModuleCreateInfo::default().code(&vert_code),
                    None,
                )
                .ok()?;
            let frag_code = ash::util::read_spv(&mut std::io::Cursor::new(frag)).ok()?;
            let frag_mod = device
                .create_shader_module(
                    &vk::ShaderModuleCreateInfo::default().code(&frag_code),
                    None,
                )
                .ok()?;
            let entry = c"main";
            let stages = [
                vk::PipelineShaderStageCreateInfo::default()
                    .stage(vk::ShaderStageFlags::VERTEX)
                    .module(vert_mod)
                    .name(entry),
                vk::PipelineShaderStageCreateInfo::default()
                    .stage(vk::ShaderStageFlags::FRAGMENT)
                    .module(frag_mod)
                    .name(entry),
            ];
            let bindings = [vk::VertexInputBindingDescription::default()
                .binding(0)
                .stride(VERTEX_SIZE as u32)
                .input_rate(vk::VertexInputRate::VERTEX)];
            let attrs = [
                vk::VertexInputAttributeDescription::default()
                    .location(0)
                    .binding(0)
                    .format(vk::Format::R32G32_SFLOAT)
                    .offset(0),
                vk::VertexInputAttributeDescription::default()
                    .location(1)
                    .binding(0)
                    .format(vk::Format::R32G32_SFLOAT)
                    .offset(8),
                vk::VertexInputAttributeDescription::default()
                    .location(2)
                    .binding(0)
                    .format(vk::Format::R32G32B32A32_SFLOAT)
                    .offset(16),
                vk::VertexInputAttributeDescription::default()
                    .location(3)
                    .binding(0)
                    .format(vk::Format::R32G32B32A32_SFLOAT)
                    .offset(32),
                vk::VertexInputAttributeDescription::default()
                    .location(4)
                    .binding(0)
                    .format(vk::Format::R32G32B32A32_SFLOAT)
                    .offset(48),
            ];
            let vertex_input = vk::PipelineVertexInputStateCreateInfo::default()
                .vertex_binding_descriptions(&bindings)
                .vertex_attribute_descriptions(&attrs);
            let input_assembly = vk::PipelineInputAssemblyStateCreateInfo::default()
                .topology(vk::PrimitiveTopology::TRIANGLE_LIST);
            let viewport_state = vk::PipelineViewportStateCreateInfo::default()
                .viewport_count(1)
                .scissor_count(1);
            let raster = vk::PipelineRasterizationStateCreateInfo::default()
                .polygon_mode(vk::PolygonMode::FILL)
                .cull_mode(vk::CullModeFlags::NONE)
                .front_face(vk::FrontFace::COUNTER_CLOCKWISE)
                .line_width(1.0);
            let multisample = vk::PipelineMultisampleStateCreateInfo::default()
                .rasterization_samples(vk::SampleCountFlags::TYPE_1);
            let blend_attach = [vk::PipelineColorBlendAttachmentState::default()
                .color_write_mask(vk::ColorComponentFlags::RGBA)
                .blend_enable(true)
                .src_color_blend_factor(vk::BlendFactor::SRC_ALPHA)
                .dst_color_blend_factor(vk::BlendFactor::ONE_MINUS_SRC_ALPHA)
                .color_blend_op(vk::BlendOp::ADD)
                .src_alpha_blend_factor(vk::BlendFactor::ONE)
                .dst_alpha_blend_factor(vk::BlendFactor::ONE_MINUS_SRC_ALPHA)
                .alpha_blend_op(vk::BlendOp::ADD)];
            let blend = vk::PipelineColorBlendStateCreateInfo::default().attachments(&blend_attach);
            let dynamic = [vk::DynamicState::VIEWPORT, vk::DynamicState::SCISSOR];
            let dynamic_state =
                vk::PipelineDynamicStateCreateInfo::default().dynamic_states(&dynamic);
            let pipeline_info = vk::GraphicsPipelineCreateInfo::default()
                .stages(&stages)
                .vertex_input_state(&vertex_input)
                .input_assembly_state(&input_assembly)
                .viewport_state(&viewport_state)
                .rasterization_state(&raster)
                .multisample_state(&multisample)
                .color_blend_state(&blend)
                .dynamic_state(&dynamic_state)
                .layout(layout)
                .render_pass(render_pass)
                .subpass(0);
            let pipeline = device
                .create_graphics_pipelines(vk::PipelineCache::null(), &[pipeline_info], None)
                .ok()
                .map(|p| p[0])?;
            device.destroy_shader_module(vert_mod, None);
            device.destroy_shader_module(frag_mod, None);
            Some(pipeline)
        };
        let pipeline_shape = make_pipeline(SHAPE_FRAGMENT)?;
        let pipeline_text = make_pipeline(TEXT_FRAGMENT)?;
        let pipeline_image = make_pipeline(IMAGE_FRAGMENT)?;
        t.timing.mark("pipelines");

        let pool = device
            .create_command_pool(
                &vk::CommandPoolCreateInfo::default()
                    .flags(vk::CommandPoolCreateFlags::RESET_COMMAND_BUFFER)
                    .queue_family_index(gfx_family),
                None,
            )
            .ok()?;
        let cmds = device
            .allocate_command_buffers(
                &vk::CommandBufferAllocateInfo::default()
                    .command_pool(pool)
                    .level(vk::CommandBufferLevel::PRIMARY)
                    .command_buffer_count(2),
            )
            .ok()?;
        let (cmd, capture_cmd) = (cmds[0], cmds[1]);
        let acquire_sem = device
            .create_semaphore(&vk::SemaphoreCreateInfo::default(), None)
            .ok()?;
        let render_sem = device
            .create_semaphore(&vk::SemaphoreCreateInfo::default(), None)
            .ok()?;
        let in_flight = device
            .create_fence(
                &vk::FenceCreateInfo::default().flags(vk::FenceCreateFlags::SIGNALED),
                None,
            )
            .ok()?;
        let (capture_vbuf, capture_vmem) = Gpu::create_buffer(
            &device,
            &mem_props,
            (MAX_VERTICES * VERTEX_SIZE) as u64,
            vk::BufferUsageFlags::VERTEX_BUFFER,
            vk::MemoryPropertyFlags::HOST_VISIBLE | vk::MemoryPropertyFlags::HOST_COHERENT,
        )?;
        let (vertex_buffer, vertex_memory) = Gpu::create_buffer(
            &device,
            &mem_props,
            (MAX_VERTICES * VERTEX_SIZE) as u64,
            vk::BufferUsageFlags::VERTEX_BUFFER,
            vk::MemoryPropertyFlags::HOST_VISIBLE | vk::MemoryPropertyFlags::HOST_COHERENT,
        )?;
        let vertex_ptr = device
            .map_memory(
                vertex_memory,
                0,
                vk::WHOLE_SIZE,
                vk::MemoryMapFlags::empty(),
            )
            .ok()? as *mut u8;
        t.timing.mark("buffers");

        let graphics_queue = device.get_device_queue(gfx_family, 0);
        let present_queue = device.get_device_queue(present_family, 0);

        Some(Gpu {
            _entry: entry,
            instance,
            surface_fn,
            surface,
            phys,
            color_space: format.color_space,
            device,
            swapchain_fn,
            mem_props,
            swapchain,
            views,
            swapchain_images: images.clone(),
            framebuffers,
            render_pass,
            extent,
            capture_size: None,
            format: format.format,
            layout,
            pipeline_shape,
            pipeline_text,
            pipeline_image,
            desc_pool,
            set_atlas,
            set_art,
            atlas_image: atlas.image,
            atlas_memory: atlas.memory,
            atlas_view: atlas.view,
            atlas_layout: vk::ImageLayout::UNDEFINED,
            sampler,
            art_image: art.image,
            art_memory: art.memory,
            art_view: art.view,
            art_size: (1, 1),
            art_uploaded: false,
            vertex_buffer,
            vertex_memory,
            capture_vbuf,
            capture_vmem,
            vertex_ptr,
            graphics_queue,
            present_queue,
            pool,
            cmd,
            capture_cmd,
            acquire_sem,
            render_sem,
            in_flight,
            last_present_index: 0,
            needs_resize: false,
            push_res: [extent.width as f32, extent.height as f32],
            text_gamma: std::env::var("PLAYER_TEXT_GAMMA")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(2.2),
        })
    }
}

pub struct Offscreen {
    image: vk::Image,
    memory: vk::DeviceMemory,
    view: vk::ImageView,
    fb: vk::Framebuffer,
    readback: vk::Buffer,
    readback_mem: vk::DeviceMemory,
    w: u32,
    h: u32,
}

impl Gpu {
    /// Copy the draw list into the persistent mapped vertex buffer. Returns vertex count.
    pub unsafe fn upload_vertices(&mut self, list: &DrawList) -> usize {
        let total = list.vertices.len();
        assert!(total <= MAX_VERTICES, "vertex budget exceeded: {total}");
        std::ptr::copy_nonoverlapping(
            list.vertices.as_ptr() as *const u8,
            self.vertex_ptr,
            total * VERTEX_SIZE,
        );
        total
    }

    /// Copy the list into the capture buffer and return a mapped pointer-free handle.
    unsafe fn upload_capture_vertices(&mut self, list: &DrawList) -> Result<usize, vk::Result> {
        let total = list.vertices.len();
        assert!(total <= MAX_VERTICES, "vertex budget exceeded: {total}");
        let ptr = self.device.map_memory(
            self.capture_vmem,
            0,
            vk::WHOLE_SIZE,
            vk::MemoryMapFlags::empty(),
        )?;
        std::ptr::copy_nonoverlapping(
            list.vertices.as_ptr() as *const u8,
            ptr as *mut u8,
            total * VERTEX_SIZE,
        );
        self.device.unmap_memory(self.capture_vmem);
        Ok(total)
    }

    unsafe fn record_sized(
        &self,
        fb: vk::Framebuffer,
        list: &DrawList,
        copy_out: Option<vk::Buffer>,
        image: vk::Image,
        clear: [f32; 4],
        extent: vk::Extent2D,
        vbuf: vk::Buffer,
    ) -> Result<(), vk::Result> {
        self.device
            .reset_command_buffer(self.cmd, vk::CommandBufferResetFlags::empty())?;
        self.device
            .begin_command_buffer(self.cmd, &vk::CommandBufferBeginInfo::default())?;
        let clear_values = [vk::ClearValue {
            color: vk::ClearColorValue {
                float32: crate::scene::linear(clear),
            },
        }];
        let rp_begin = vk::RenderPassBeginInfo::default()
            .render_pass(self.render_pass)
            .framebuffer(fb)
            .render_area(vk::Rect2D {
                offset: vk::Offset2D { x: 0, y: 0 },
                extent,
            })
            .clear_values(&clear_values);
        self.device
            .cmd_begin_render_pass(self.cmd, &rp_begin, vk::SubpassContents::INLINE);
        let viewport = [vk::Viewport {
            x: 0.0,
            y: 0.0,
            width: extent.width as f32,
            height: extent.height as f32,
            min_depth: 0.0,
            max_depth: 1.0,
        }];
        self.device.cmd_set_viewport(self.cmd, 0, &viewport);
        // Logical resolution: on a HiDPI surface the layout is in logical units, so the
        // shader must divide by the logical size even though the swapchain is physical.
        // xy = logical resolution, z = text gamma, w = reserved
        let params = [self.push_res[0], self.push_res[1], self.text_gamma, 0.0];
        let res_bytes = std::slice::from_raw_parts(params.as_ptr() as *const u8, 16);
        self.device
            .cmd_bind_vertex_buffers(self.cmd, 0, &[vbuf], &[0]);
        self.device.cmd_push_constants(
            self.cmd,
            self.layout,
            vk::ShaderStageFlags::VERTEX,
            0,
            res_bytes,
        );

        let mut bound: Option<Kind> = None;
        for Batch {
            kind,
            first,
            count,
            scissor,
        } in list.batches.iter().copied()
        {
            // Clip rects arrive in logical units (the frame's layout space) while the scissor is
            // applied to the physical framebuffer, so they have to be scaled - otherwise a 2x
            // surface clips every list to half its height.
            let k = extent.width as f32 / self.push_res[0].max(1.0);
            let rect = scissor
                .map(|[x, y, w, h]| {
                    let (x, y) = (x.max(0.0) * k, y.max(0.0) * k);
                    vk::Rect2D {
                        offset: vk::Offset2D {
                            x: x as i32,
                            y: y as i32,
                        },
                        extent: vk::Extent2D {
                            width: ((w.max(0.0) * k) as u32)
                                .min(extent.width.saturating_sub(x as u32)),
                            height: ((h.max(0.0) * k) as u32)
                                .min(extent.height.saturating_sub(y as u32)),
                        },
                    }
                })
                .unwrap_or(vk::Rect2D {
                    offset: vk::Offset2D { x: 0, y: 0 },
                    extent: self.extent,
                });
            if rect.extent.width == 0 || rect.extent.height == 0 {
                continue;
            }
            self.device.cmd_set_scissor(self.cmd, 0, &[rect]);
            if bound != Some(kind) {
                match kind {
                    Kind::Shape => {
                        self.device.cmd_bind_pipeline(
                            self.cmd,
                            vk::PipelineBindPoint::GRAPHICS,
                            self.pipeline_shape,
                        );
                    }
                    Kind::Text => {
                        self.device.cmd_bind_pipeline(
                            self.cmd,
                            vk::PipelineBindPoint::GRAPHICS,
                            self.pipeline_text,
                        );
                        self.device.cmd_bind_descriptor_sets(
                            self.cmd,
                            vk::PipelineBindPoint::GRAPHICS,
                            self.layout,
                            0,
                            &[self.set_atlas],
                            &[],
                        );
                    }
                    Kind::Image => {
                        self.device.cmd_bind_pipeline(
                            self.cmd,
                            vk::PipelineBindPoint::GRAPHICS,
                            self.pipeline_image,
                        );
                        self.device.cmd_bind_descriptor_sets(
                            self.cmd,
                            vk::PipelineBindPoint::GRAPHICS,
                            self.layout,
                            0,
                            &[self.set_art],
                            &[],
                        );
                    }
                }
                bound = Some(kind);
            }
            self.device.cmd_draw(self.cmd, count, 1, first, 0);
        }
        self.device.cmd_end_render_pass(self.cmd);
        if copy_out.is_some() {
            // The render pass declares PRESENT_SRC_KHR as its final layout (it also serves the
            // swapchain), so the offscreen image is NOT in COLOR_ATTACHMENT_OPTIMAL here. Using
            // the wrong oldLayout is undefined behaviour: llvmpipe answered with a SIGSEGV in
            // util_copy_rect, RADV silently tolerated it.
            let to_src = vk::ImageMemoryBarrier::default()
                .old_layout(vk::ImageLayout::PRESENT_SRC_KHR)
                .new_layout(vk::ImageLayout::TRANSFER_SRC_OPTIMAL)
                .src_queue_family_index(vk::QUEUE_FAMILY_IGNORED)
                .dst_queue_family_index(vk::QUEUE_FAMILY_IGNORED)
                .image(image)
                .subresource_range(
                    vk::ImageSubresourceRange::default()
                        .aspect_mask(vk::ImageAspectFlags::COLOR)
                        .level_count(1)
                        .layer_count(1),
                )
                .src_access_mask(vk::AccessFlags::COLOR_ATTACHMENT_WRITE)
                .dst_access_mask(vk::AccessFlags::TRANSFER_READ);
            self.device.cmd_pipeline_barrier(
                self.cmd,
                vk::PipelineStageFlags::COLOR_ATTACHMENT_OUTPUT,
                vk::PipelineStageFlags::TRANSFER,
                vk::DependencyFlags::empty(),
                &[],
                &[],
                &[to_src],
            );
            self.device.cmd_copy_image_to_buffer(
                self.cmd,
                image,
                vk::ImageLayout::TRANSFER_SRC_OPTIMAL,
                copy_out.unwrap(),
                &[vk::BufferImageCopy::default()
                    .image_subresource(
                        vk::ImageSubresourceLayers::default()
                            .aspect_mask(vk::ImageAspectFlags::COLOR)
                            .layer_count(1),
                    )
                    .image_extent(vk::Extent3D {
                        width: self.extent.width,
                        height: self.extent.height,
                        depth: 1,
                    })],
            );
        }
        self.device.end_command_buffer(self.cmd)?;
        Ok(())
    }

    pub unsafe fn submit_and_wait(&self) -> Result<(), vk::Result> {
        let cmds = [self.cmd];
        let submit = vk::SubmitInfo::default().command_buffers(&cmds);
        self.device
            .queue_submit(self.graphics_queue, &[submit], vk::Fence::null())?;
        self.device.queue_wait_idle(self.graphics_queue)?;
        Ok(())
    }

    /// Present one frame from `list` to the swapchain.
    pub unsafe fn draw(&mut self, list: &DrawList, clear: [f32; 4]) -> Result<(), vk::Result> {
        self.device
            .wait_for_fences(&[self.in_flight], true, u64::MAX)?;
        let (idx, subopt) = self.swapchain_fn.acquire_next_image(
            self.swapchain,
            u64::MAX,
            self.acquire_sem,
            vk::Fence::null(),
        )?;
        self.device.reset_fences(&[self.in_flight])?;
        // The frame's geometry has to be copied into the vertex buffer *before* recording:
        // without this the swapchain path renders the clear colour only (the offscreen capture
        // path uploads into its own buffer, which is why screenshots looked fine while the
        // window stayed black).
        self.upload_vertices(list);
        let fb = self.framebuffers[idx as usize];
        self.record_sized(
            fb,
            list,
            None,
            vk::Image::null(),
            clear,
            self.extent,
            self.vertex_buffer,
        )?;

        let wait = [self.acquire_sem];
        let stages = [vk::PipelineStageFlags::COLOR_ATTACHMENT_OUTPUT];
        let sig = [self.render_sem];
        let cmds = [self.cmd];
        let submit = vk::SubmitInfo::default()
            .wait_semaphores(&wait)
            .wait_dst_stage_mask(&stages)
            .command_buffers(&cmds)
            .signal_semaphores(&sig);
        self.device
            .queue_submit(self.graphics_queue, &[submit], self.in_flight)?;
        let swapchains = [self.swapchain];
        let indices = [idx];
        let present = vk::PresentInfoKHR::default()
            .wait_semaphores(&sig)
            .swapchains(&swapchains)
            .image_indices(&indices);
        self.swapchain_fn
            .queue_present(self.present_queue, &present)?;
        Ok(())
    }

    /// Logical resolution for the vertex shader (physical size / scale factor).
    pub fn set_push_res(&mut self, w: f32, h: f32) {
        self.push_res = [w.max(1.0), h.max(1.0)];
    }

    /// Fixed size for every offscreen capture, independent of compositor tiling.
    pub fn set_capture_size(&mut self, size: Option<(u32, u32)>) {
        self.capture_size = size;
    }

    /// Copy the swapchain image we just presented into a PPM. Ground truth for "the window is
    /// black": shows whether the bad pixels are ours or the compositor's.
    pub unsafe fn dump_presented(&mut self, index: u32, path: &str) -> Result<(), vk::Result> {
        self.device.device_wait_idle()?;
        let (w, h) = (self.extent.width, self.extent.height);
        let size = (w as u64) * (h as u64) * 4;
        let (buf, mem) = Gpu::create_buffer(
            &self.device,
            &self.mem_props,
            size,
            vk::BufferUsageFlags::TRANSFER_DST,
            vk::MemoryPropertyFlags::HOST_VISIBLE | vk::MemoryPropertyFlags::HOST_COHERENT,
        )
        .ok_or(vk::Result::ERROR_OUT_OF_DEVICE_MEMORY)?;
        self.device
            .reset_command_buffer(self.cmd, vk::CommandBufferResetFlags::empty())?;
        self.device
            .begin_command_buffer(self.cmd, &vk::CommandBufferBeginInfo::default())?;
        let range = vk::ImageSubresourceRange::default()
            .aspect_mask(vk::ImageAspectFlags::COLOR)
            .level_count(1)
            .layer_count(1);
        let to_src = vk::ImageMemoryBarrier::default()
            .old_layout(vk::ImageLayout::PRESENT_SRC_KHR)
            .new_layout(vk::ImageLayout::TRANSFER_SRC_OPTIMAL)
            .src_queue_family_index(vk::QUEUE_FAMILY_IGNORED)
            .dst_queue_family_index(vk::QUEUE_FAMILY_IGNORED)
            .image(self.swapchain_images[index as usize])
            .subresource_range(range)
            .src_access_mask(vk::AccessFlags::MEMORY_READ)
            .dst_access_mask(vk::AccessFlags::TRANSFER_READ);
        self.device.cmd_pipeline_barrier(
            self.cmd,
            vk::PipelineStageFlags::ALL_COMMANDS,
            vk::PipelineStageFlags::TRANSFER,
            vk::DependencyFlags::empty(),
            &[],
            &[],
            &[to_src],
        );
        self.device.cmd_copy_image_to_buffer(
            self.cmd,
            self.swapchain_images[index as usize],
            vk::ImageLayout::TRANSFER_SRC_OPTIMAL,
            buf,
            &[vk::BufferImageCopy::default()
                .image_subresource(
                    vk::ImageSubresourceLayers::default()
                        .aspect_mask(vk::ImageAspectFlags::COLOR)
                        .layer_count(1),
                )
                .image_extent(vk::Extent3D {
                    width: w,
                    height: h,
                    depth: 1,
                })],
        );
        let back = vk::ImageMemoryBarrier::default()
            .old_layout(vk::ImageLayout::TRANSFER_SRC_OPTIMAL)
            .new_layout(vk::ImageLayout::PRESENT_SRC_KHR)
            .src_queue_family_index(vk::QUEUE_FAMILY_IGNORED)
            .dst_queue_family_index(vk::QUEUE_FAMILY_IGNORED)
            .image(self.swapchain_images[index as usize])
            .subresource_range(range)
            .src_access_mask(vk::AccessFlags::TRANSFER_READ)
            .dst_access_mask(vk::AccessFlags::MEMORY_READ);
        self.device.cmd_pipeline_barrier(
            self.cmd,
            vk::PipelineStageFlags::TRANSFER,
            vk::PipelineStageFlags::ALL_COMMANDS,
            vk::DependencyFlags::empty(),
            &[],
            &[],
            &[back],
        );
        self.device.end_command_buffer(self.cmd)?;
        let cmds = [self.cmd];
        self.device.queue_submit(
            self.graphics_queue,
            &[vk::SubmitInfo::default().command_buffers(&cmds)],
            vk::Fence::null(),
        )?;
        self.device.device_wait_idle()?;
        let ptr = self
            .device
            .map_memory(mem, 0, vk::WHOLE_SIZE, vk::MemoryMapFlags::empty())?
            as *const u8;
        let pixels = std::slice::from_raw_parts(ptr, size as usize).to_vec();
        self.device.unmap_memory(mem);
        self.device.destroy_buffer(buf, None);
        self.device.free_memory(mem, None);
        let mut out = Vec::with_capacity(size as usize * 3 / 4 + 32);
        out.extend_from_slice(format!("P6\n{w} {h}\n255\n").as_bytes());
        for px in pixels.chunks_exact(4) {
            out.extend_from_slice(&[px[2], px[1], px[0]]);
        }
        std::fs::write(path, &out).ok();
        println!("dumped presented frame to {path} ({w}x{h})");
        Ok(())
    }

    pub unsafe fn make_offscreen(&mut self) -> Result<Offscreen, vk::Result> {
        let (w, h) = self
            .capture_size
            .unwrap_or((self.extent.width, self.extent.height));
        self.make_offscreen_sized(w, h)
    }

    /// Offscreen target with an explicit size, so captures do not depend on how the compositor
    /// happened to tile the window.
    pub unsafe fn make_offscreen_sized(&mut self, w: u32, h: u32) -> Result<Offscreen, vk::Result> {
        // Must match the render pass attachment format (the swapchain's), otherwise the
        // framebuffer/render-pass pair is invalid and the driver writes outside the image:
        // observed as a SIGSEGV in llvmpipe's util_copy_rect.
        let format = self.format;
        let img = Gpu::create_image(
            &self.device,
            &self.mem_props,
            w,
            h,
            format,
            vk::ImageUsageFlags::COLOR_ATTACHMENT | vk::ImageUsageFlags::TRANSFER_SRC,
        )
        .ok_or(vk::Result::ERROR_OUT_OF_DEVICE_MEMORY)?;
        let fb = self.device.create_framebuffer(
            &vk::FramebufferCreateInfo::default()
                .render_pass(self.render_pass)
                .attachments(std::slice::from_ref(&img.view))
                .width(w)
                .height(h)
                .layers(1),
            None,
        )?;
        let size = (w * h * 4) as u64;
        let (readback, readback_mem) = Gpu::create_buffer(
            &self.device,
            &self.mem_props,
            size,
            vk::BufferUsageFlags::TRANSFER_DST,
            vk::MemoryPropertyFlags::HOST_VISIBLE | vk::MemoryPropertyFlags::HOST_COHERENT,
        )
        .ok_or(vk::Result::ERROR_OUT_OF_DEVICE_MEMORY)?;
        Ok(Offscreen {
            image: img.image,
            memory: img.memory,
            view: img.view,
            fb,
            readback,
            readback_mem,
            w,
            h,
        })
    }

    pub unsafe fn destroy_offscreen(&mut self, o: Offscreen) {
        self.device.destroy_buffer(o.readback, None);
        self.device.free_memory(o.readback_mem, None);
        self.device.destroy_framebuffer(o.fb, None);
        let img = ImageAlloc {
            image: o.image,
            memory: o.memory,
            view: o.view,
        };
        self.destroy_image(img);
    }

    /// Render `list` offscreen and write it as binary PPM.
    pub unsafe fn shot(
        &mut self,
        list: &DrawList,
        path: &str,
        clear: [f32; 4],
    ) -> Result<(), vk::Result> {
        self.wait_idle()?;
        std::mem::swap(&mut self.cmd, &mut self.capture_cmd);
        let off = self.make_offscreen()?;
        let extent = vk::Extent2D {
            width: off.w,
            height: off.h,
        };
        if std::env::var("PROTO_DEBUG_GPU").is_ok() {
            let req_img = self.device.get_image_memory_requirements(off.image);
            let req_buf = self.device.get_buffer_memory_requirements(off.readback);
            eprintln!(
                "[gpu] shot pre-submit {}x{} image_req={} buffer_req={} needed={} format={:?}",
                off.w,
                off.h,
                req_img.size,
                req_buf.size,
                off.w as u64 * off.h as u64 * 4,
                self.format
            );
        }
        self.upload_capture_vertices(list)?;
        self.record_sized(
            off.fb,
            list,
            Some(off.readback),
            off.image,
            clear,
            extent,
            self.capture_vbuf,
        )?;
        self.submit_and_wait()?;

        let size = (off.w * off.h * 4) as usize;
        let ptr = self.device.map_memory(
            off.readback_mem,
            0,
            vk::WHOLE_SIZE,
            vk::MemoryMapFlags::empty(),
        )? as *const u8;
        let pixels = std::slice::from_raw_parts(ptr, size).to_vec();
        self.device.unmap_memory(off.readback_mem);

        let mut out = Vec::with_capacity(size * 3 / 4 + 32);
        out.extend_from_slice(format!("P6\n{} {}\n255\n", off.w, off.h).as_bytes());
        for px in pixels.chunks_exact(4) {
            out.extend_from_slice(&[px[2], px[1], px[0]]);
        }
        std::fs::write(path, &out).map_err(|e| {
            eprintln!("write {path} failed: {e}");
            vk::Result::ERROR_UNKNOWN
        })?;
        println!("wrote {path} ({}x{})", off.w, off.h);
        self.destroy_offscreen(off);
        std::mem::swap(&mut self.cmd, &mut self.capture_cmd);
        Ok(())
    }

    /// Frame-time statistics for the render path only: record + submit + wait, no compositor.
    pub unsafe fn bench(
        &mut self,
        list: &DrawList,
        frames: u32,
        clear: [f32; 4],
    ) -> Result<(), vk::Result> {
        self.wait_idle()?;
        let off = self.make_offscreen()?;
        let extent = vk::Extent2D {
            width: off.w,
            height: off.h,
        };
        let vertices = self.upload_capture_vertices(list)?;
        self.record_sized(
            off.fb,
            list,
            None,
            vk::Image::null(),
            clear,
            extent,
            self.capture_vbuf,
        )?;
        self.submit_and_wait()?;

        let mut samples = Vec::with_capacity(frames as usize);
        for _ in 0..frames {
            let t = std::time::Instant::now();
            self.record_sized(
                off.fb,
                list,
                None,
                vk::Image::null(),
                clear,
                extent,
                self.capture_vbuf,
            )?;
            self.submit_and_wait()?;
            samples.push(t.elapsed().as_secs_f64() * 1000.0);
        }
        samples.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let n = samples.len();
        let sum: f64 = samples.iter().sum();
        let q = |p: f64| samples[((p * (n - 1) as f64).round() as usize).min(n - 1)];
        println!(
            "bench: {}x{} | {} vertices | {} batches | {} frames",
            off.w,
            off.h,
            vertices,
            list.batches.len(),
            n
        );
        println!(
            "frame: min {:.3}  p50 {:.3}  p95 {:.3}  max {:.3}  mean {:.3} ms  => {:.0} fps (p50)",
            samples[0],
            q(0.50),
            q(0.95),
            samples[n - 1],
            sum / n as f64,
            1000.0 / q(0.50)
        );
        self.destroy_offscreen(off);
        Ok(())
    }
}
